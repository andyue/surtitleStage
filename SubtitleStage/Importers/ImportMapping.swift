import Foundation

public enum ImportMapping {
    public static func rows(sheet: SpreadsheetSheet, configuration: ImportConfiguration, languages: [LanguageLayer]) throws -> [DocumentImportRow] {
        guard configuration.headerRow >= 0 else { throw ProjectError.invalid("Header row must be zero or a positive row number.") }
        let roles = configuration.columns.values.filter { $0 != .ignore }
        guard roles.contains(where: { if case .text = $0 { return true }; return $0 == .dialogue }) else {
            throw ProjectError.invalid("Map at least one text column to a Surtitle or Dialogue.")
        }
        let uniqueRoles = roles.map { String(describing: $0) }
        guard Set(uniqueRoles).count == uniqueRoles.count else { throw ProjectError.invalid("Each destination or metadata field can be mapped only once.") }
        guard !roles.contains(.target) || roles.contains(.dialogue) else { throw ProjectError.invalid("Target routing requires a Dialogue column.") }
        guard languages.contains(where: { $0.id == configuration.defaultLayerID }) else { throw ProjectError.invalid("Default Surtitle is missing.") }
        for (column, role) in configuration.columns where role != .ignore {
            guard column >= 0, column < sheet.columnCount else { throw ProjectError.invalid("A mapped column is missing in this worksheet.") }
            if case let .text(id) = role, !languages.contains(where: { $0.id == id }) { throw ProjectError.invalid("A mapped Surtitle no longer exists.") }
        }
        if configuration.headerRow != 0, !sheet.rows.contains(where: { $0.number == configuration.headerRow }) {
            throw ProjectError.invalid("The selected header row does not exist.")
        }
        return try sheet.rows.filter { $0.number > configuration.headerRow }.map { source in
            var row = DocumentImportRow(); row.location = "\(sheet.name) row \(source.number)"
            if source.ignoredByDefault {
                row.ignored = true
                row.warnings.append("Disabled in source: ignored by default.")
            }
            var dialogue: String?, target = ""
            for (index, role) in configuration.columns {
                let value = source.cells[index] ?? ""
                switch role {
                case .ignore: break
                case .key: row.key = value.trimmingCharacters(in: .whitespacesAndNewlines)
                case .number: row.content.number = value
                case .speaker: row.content.speaker = value
                case .note: row.content.note = value
                case .target: target = value.trimmingCharacters(in: .whitespacesAndNewlines)
                case .dialogue: dialogue = value
                case .text(let id): row.content.texts[id] = value
                }
            }
            if let dialogue {
                let destination: UUID
                if target.isEmpty { destination = configuration.defaultLayerID }
                else {
                    let matches = languages.filter { $0.name == target || $0.id.uuidString.lowercased() == target.lowercased() }
                    guard matches.count == 1, let match = matches.first else {
                        throw ProjectError.invalid("\(row.location): Target ‘\(target)’ must uniquely match a Surtitle name or UUID.")
                    }
                    destination = match.id
                }
                guard row.content.texts[destination] == nil else { throw ProjectError.invalid("\(row.location): Dialogue and another column target the same Surtitle.") }
                row.content.texts[destination] = dialogue
            }
            if !roles.contains(.key) { row.key = UUID().uuidString }
            if row.content.texts.values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                row.ignored = true; row.warnings.append("Empty dialogue: ignored by default.")
            }
            return row
        }
    }
}

public enum ImportWorkspaceEditing {
    public static func split(_ row: DocumentImportRow) throws -> [DocumentImportRow] {
        let lines = row.content.texts.mapValues { $0.components(separatedBy: "\n") }
        let count = lines.values.map(\.count).max() ?? 0
        guard count > 1 else { throw ProjectError.invalid("Insert line breaks before splitting this row.") }
        guard lines.values.allSatisfy({ $0.count == count || $0.allSatisfy(\.isEmpty) }) else {
            throw ProjectError.invalid("For a multilingual split, each non-empty Surtitle must have the same number of lines.")
        }
        return (0..<count).map { index in
            var part = row; part.id = UUID()
            part.key = index == 0 ? row.key : row.key + "#part\(index + 1)"
            part.content.texts = lines.mapValues { $0.indices.contains(index) ? $0[index] : "" }
            part.location += " · part \(index + 1)"
            if index > 0 { part.content.number = nil }
            return part
        }
    }
    public static func merge(_ rows: [DocumentImportRow]) throws -> DocumentImportRow {
        guard var result = rows.first, rows.count > 1 else { throw ProjectError.invalid("Select at least two rows to merge.") }
        guard rows.allSatisfy({ $0.content.speaker == result.content.speaker }) else {
            throw ProjectError.invalid("Assign the same speaker before merging rows.")
        }
        let layers = Set(rows.flatMap { $0.content.texts.keys })
        result.content.texts = Dictionary(uniqueKeysWithValues: layers.map { id in
            (id, rows.compactMap { $0.content.texts[id] }.joined(separator: "\n"))
        })
        result.content.note = rows.compactMap(\.content.note).filter { !$0.isEmpty }.joined(separator: "\n")
        result.warnings += ["Merged rows retain the first source key and number; review subsequent re-imports."]
        for id in layers {
            if !rows.allSatisfy({ $0.content.traits[id] == result.content.traits[id] }) { result.content.traits[id] = nil }
        }
        return result
    }
}
