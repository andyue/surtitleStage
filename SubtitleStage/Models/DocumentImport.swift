import Foundation

public struct ImportTextTraits: Codable, Equatable, Sendable {
    public var bold = false
    public var italic = false
    public var underline = false
    public init() {}
}
public struct ImportedContent: Codable, Equatable, Sendable {
    public var number: String?
    public var speaker: String?
    public var note: String?
    public var texts: [UUID: String] = [:]
    public var traits: [UUID: ImportTextTraits] = [:]
    public init() {}
}
public struct CueImportOrigin: Codable, Equatable, Sendable {
    public var sourceID: UUID
    public var key: String
    public var baseline: ImportedContent
}
public enum ImportColumn: Codable, Equatable, Sendable {
    case ignore, key, number, speaker, note, target, dialogue
    case text(UUID)
}
public struct ImportConfiguration: Codable, Equatable, Sendable {
    public var sheet = ""
    public var headerRow = 1 // 0 means no header; otherwise physical spreadsheet row.
    public var columns: [Int: ImportColumn] = [:]
    public var defaultLayerID: UUID
    public init(defaultLayerID: UUID) { self.defaultLayerID = defaultLayerID }
}
public struct ImportSource: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: String
    public var configuration: ImportConfiguration
    public var hasStableKeys: Bool
    public init(id: UUID = UUID(), name: String, kind: String, configuration: ImportConfiguration, hasStableKeys: Bool) {
        self.id = id; self.name = name; self.kind = kind; self.configuration = configuration; self.hasStableKeys = hasStableKeys
    }
}
public struct DocumentImportRow: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var key = ""
    public var location = ""
    public var content = ImportedContent()
    public var ignored = false
    public var warnings: [String] = []
    public init() {}
}
public struct SpreadsheetRow: Sendable, Equatable {
    public let number: Int
    public let cells: [Int: String]
    public var ignoredByDefault = false
}
public struct SpreadsheetSheet: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let rows: [SpreadsheetRow]
    public var columnCount: Int { (rows.flatMap { $0.cells.keys }.max() ?? -1) + 1 }
    public var suggestedHeader: Int {
        rows.prefix(20).first(where: { row in
            let nonempty = row.cells.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return nonempty.count >= 2 && Set(nonempty).count == nonempty.count && nonempty.allSatisfy { Double($0) == nil }
        })?.number ?? 0
    }
}
public struct ParsedDocument: Sendable {
    public var kind: String
    public var sheets: [SpreadsheetSheet] = []
    public var rows: [DocumentImportRow] = []
    public var warnings: [String] = []
}
