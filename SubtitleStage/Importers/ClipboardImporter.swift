import Foundation

public enum ClipboardMode: String, CaseIterable, Sendable { case line, paragraph }
public struct ImportItem: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let text: String
}
public enum ClipboardImporter {
    public static func parse(_ source: String, mode: ClipboardMode) -> [ImportItem] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [String] = []
        var paragraph: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if mode == .line {
                if !trimmed.isEmpty { result.append(trimmed) }
            } else if trimmed.isEmpty {
                if !paragraph.isEmpty { result.append(paragraph.joined(separator: "\n")); paragraph = [] }
            } else { paragraph.append(line) }
        }
        if !paragraph.isEmpty { result.append(paragraph.joined(separator: "\n")) }
        return result.map { ImportItem(text: $0) }
    }
}
