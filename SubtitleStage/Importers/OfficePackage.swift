import Foundation


/// Reads individual ZIP members without extracting paths to disk.
final class OfficePackage {
    let url: URL
    let entries: Set<String>
    private var consumed = 0
    init(url: URL) throws {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 50_000_000 else {
            throw ProjectError.invalid("Document is larger than the 50 MB import limit.")
        }
        self.url = url
        let list = try Self.command(["-Z1", url.path], limit: 1_000_000)
        guard let listing = String(data: list, encoding: .utf8) else { throw ProjectError.invalid("Invalid Office archive directory.") }
        let names = listing.split(separator: "\n").map(String.init)
        guard names.count <= 5000, Set(names).count == names.count else { throw ProjectError.invalid("Office archive has duplicate entries or too many parts.") }
        entries = Set(names)
    }
    func read(_ name: String) throws -> Data {
        guard entries.contains(name), !name.contains(".."), !name.hasPrefix("/"), !name.contains(where: { "*?[]\\".contains($0) }) else {
            throw ProjectError.invalid("Office document part is missing or invalid: \(name)")
        }
        let data = try Self.command(["-p", url.path, name], limit: 20_000_000)
        consumed += data.count
        guard consumed <= 100_000_000 else { throw ProjectError.invalid("Expanded document exceeds the 100 MB import limit.") }
        return data
    }
    private static func command(_ arguments: [String], limit: Int) throws -> Data {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchSource.makeTimerSource(queue: .global())
        timeout.schedule(deadline: .now() + 15)
        timeout.setEventHandler { if process.isRunning { process.terminate() } }
        timeout.resume()
        defer { timeout.cancel(); if process.isRunning { process.terminate() }; process.waitUntilExit() }
        var data = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
            try Task.checkCancellation()
            guard data.count + chunk.count <= limit else { throw ProjectError.invalid("Office document part exceeds the import size limit.") }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProjectError.invalid("Office archive cannot be read. It may be invalid, encrypted, or timed out.") }
        return data
    }
}

final class OfficeNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [OfficeNode] = []
    init(_ name: String, _ attributes: [String: String]) {
        self.name = name.split(separator: ":").last.map(String.init) ?? name
        self.attributes = Dictionary(attributes.map { ($0.key.split(separator: ":").last.map(String.init) ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
    }
    func child(_ name: String) -> OfficeNode? { children.first { $0.name == name } }
    func descendants(_ name: String) -> [OfficeNode] { children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) } }
    var allText: String { text + children.map(\.allText).joined() }
}

final class OfficeXML: NSObject, XMLParserDelegate {
    private var stack: [OfficeNode] = []
    private var root: OfficeNode?
    private var count = 0
    private var rejected = false
    static func parse(_ data: Data) throws -> OfficeNode {
        // Entity expansion is not part of Office content; reject DTDs entirely.
        guard !String(decoding: data.filter { $0 != 0 }, as: UTF8.self).uppercased().contains("<!DOCTYPE") else {
            throw ProjectError.invalid("Office XML with a DTD is not supported.")
        }
        let delegate = OfficeXML(); let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), !delegate.rejected, let root = delegate.root else {
            throw ProjectError.invalid("Invalid or excessively complex Office XML: \(parser.parserError?.localizedDescription ?? "structure limit")")
        }
        return root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        count += 1
        guard count <= 300_000, stack.count < 64, !Task.isCancelled else { rejected = true; parser.abortParsing(); return }
        let node = OfficeNode(elementName, attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { stack.last?.text += String(decoding: CDATABlock, as: UTF8.self) }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
}
