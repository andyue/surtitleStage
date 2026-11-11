import Foundation

public enum ImportChange: String, Sendable { case unchanged = "UNCHANGED", modified = "MODIFIED", new = "NEW", deleted = "DELETED" }
public struct ImportDiffItem: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let change: ImportChange
    public let cueID: UUID?
    public let incoming: DocumentImportRow?
    public let conflict: Bool
    public let detail: String
}
/// A preview-time matching choice, never a persistent cue identity.
public enum ImportMatchMode: String, Sendable { case source, cueNumber }

public struct ImportPlan: Sendable {
    public var matchMode: ImportMatchMode = .source
    public let source: ImportSource
    public let items: [ImportDiffItem]
}
public enum ImportDiff {
    public static func plan(project: Project, source: ImportSource, rows: [DocumentImportRow], reimport: Bool, matchMode: ImportMatchMode = .source) throws -> ImportPlan {
        guard rows.count <= 10_000 else { throw ProjectError.invalid("Import exceeds 10,000 rows.") }
        guard Set(rows.map(\.id)).count == rows.count else { throw ProjectError.invalid("Duplicate preview row identifiers.") }
        for row in rows where !row.ignored {
            guard !row.content.texts.isEmpty, row.content.texts.keys.allSatisfy({ id in project.languages.contains { $0.id == id } }) else {
                throw ProjectError.invalid("\(row.location): assign valid Surtitle destinations.")
            }
        }
        if matchMode == .cueNumber { return try numberPlan(project: project, source: source, rows: rows) }
        let keys = rows.map(\.key)
        guard keys.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), Set(keys).count == keys.count else {
            throw ProjectError.invalid("Source keys must be non-empty and unique. Choose a stable ID column or correct the preview keys.")
        }
        if reimport {
            guard source.hasStableKeys, project.importSources.contains(where: { $0.id == source.id }) else {
                throw ProjectError.invalid("Re-import requires a previously imported source with stable external keys.")
            }
        }
        let existing = project.cues.filter { $0.importOrigin?.sourceID == source.id }
        var byKey: [String: Cue] = [:]
        for cue in existing {
            guard let key = cue.importOrigin?.key, byKey[key] == nil else { throw ProjectError.invalid("Existing import bindings are ambiguous.") }
            byKey[key] = cue
        }
        var items: [ImportDiffItem] = []
        for row in rows where !row.ignored {
            try Task.checkCancellation()
            if let cue = byKey[row.key], let origin = cue.importOrigin {
                let changed = row.content != origin.baseline
                let conflicts = conflictFields(cue: cue, project: project, old: origin.baseline, incoming: row.content)
                items.append(ImportDiffItem(key: row.key, change: changed ? .modified : .unchanged, cueID: cue.id,
                                            incoming: row, conflict: changed && !conflicts.isEmpty,
                                            detail: conflicts.isEmpty ? "Production formatting and transitions are preserved." : "Local edits: " + conflicts.joined(separator: ", ")))
            } else {
                items.append(ImportDiffItem(key: row.key, change: .new, cueID: nil, incoming: row, conflict: false, detail: "Creates a new Cue UUID."))
            }
        }
        let present = Set(keys) // Ignored rows protect their existing cue from deletion.
        for cue in existing {
            guard let key = cue.importOrigin?.key, !present.contains(key) else { continue }
            items.append(ImportDiffItem(key: key, change: .deleted, cueID: cue.id, incoming: nil, conflict: false,
                                        detail: "Missing from source. Kept unless explicitly checked for deletion."))
        }
        return ImportPlan(source: source, items: items)
    }
    /// Resolve the explicitly selected number match to UUIDs once, against the preview snapshot.
    private static func numberPlan(project: Project, source: ImportSource, rows: [DocumentImportRow]) throws -> ImportPlan {
        func normalized(_ number: String) -> String { number.trimmingCharacters(in: .whitespacesAndNewlines) }
        let existing = Dictionary(grouping: project.cues, by: { normalized($0.displayNumber) })
        var seen = Set<String>()
        var items: [ImportDiffItem] = []
        for original in rows where !original.ignored {
            try Task.checkCancellation()
            let number = normalized(original.content.number ?? "")
            guard !number.isEmpty else {
                throw ProjectError.invalid("\(original.location): Merge by Cue Number requires a non-empty Cue Number. Map the number column or edit the preview.")
            }
            guard seen.insert(number).inserted else {
                throw ProjectError.invalid("Import contains more than one row for Cue Number ‘\(number)’. Correct or ignore duplicate rows before merging.")
            }
            let matches = existing[number] ?? []
            guard matches.count <= 1 else {
                throw ProjectError.invalid("Show contains multiple cues numbered ‘\(number)’. Give them unique numbers before merging. Nothing was applied.")
            }
            var row = original
            // Preview identifiers are independent of any optional source ID column.
            row.key = row.id.uuidString
            if let cue = matches.first {
                let changed = row.content.texts.contains { project.text(for: cue, languageID: $0.key) != $0.value }
                let overwritten = row.content.texts.keys.filter {
                    let current = project.text(for: cue, languageID: $0)
                    return !current.isEmpty && current != row.content.texts[$0]
                }
                row.content.number = cue.displayNumber
                row.content.speaker = nil; row.content.note = nil; row.content.traits = [:]
                let detail = overwritten.isEmpty
                    ? "Merge into Cue \(cue.displayNumber). Only mapped Surtitle text changes; other content and settings are preserved."
                    : "Cue \(cue.displayNumber): replaces existing text in " + project.languages.filter { overwritten.contains($0.id) }.map(\.name).joined(separator: ", ")
                items.append(ImportDiffItem(key: row.key, change: changed ? .modified : .unchanged,
                                            cueID: cue.id, incoming: row, conflict: !overwritten.isEmpty, detail: detail))
            } else {
                items.append(ImportDiffItem(key: row.key, change: .new, cueID: nil, incoming: row, conflict: false,
                                            detail: "No matching Cue Number ‘\(number)’. Creates a new cue if checked."))
            }
        }
        return ImportPlan(matchMode: .cueNumber, source: source, items: items)
    }
    private static func conflictFields(cue: Cue, project: Project, old: ImportedContent, incoming: ImportedContent) -> [String] {
        var fields: [String] = []
        for (id, value) in incoming.texts {
            let current = project.text(for: cue, languageID: id)
            if current != old.texts[id], current != value { fields.append(project.languages.first { $0.id == id }?.name ?? "Text") }
        }
        if let value = incoming.number, cue.displayNumber != old.number, cue.displayNumber != value { fields.append("Number") }
        if let value = incoming.speaker, cue.speaker != old.speaker, cue.speaker != value { fields.append("Speaker") }
        if let value = incoming.note, cue.note != old.note, cue.note != value { fields.append("Notes") }
        return fields
    }
    public static func applying(_ plan: ImportPlan, selectedKeys: Set<String>, to project: Project, after cueID: UUID?, liveCueID: UUID?) throws -> Project {
        let selected = plan.items.filter { selectedKeys.contains($0.key) && $0.change != .unchanged }
        if let liveCueID, selected.contains(where: { $0.cueID == liveCueID }) {
            throw ProjectError.invalid("The import would change or delete the live cue. Uncheck it or take another cue first. Nothing was applied.")
        }
        var result = project
        var additions: [Cue] = []
        for item in selected {
            try Task.checkCancellation()
            if item.change == .deleted {
                result.cues.removeAll { $0.id == item.cueID }
                continue
            }
            guard let row = item.incoming else { continue }
            let index = result.cues.firstIndex { $0.id == item.cueID }
            var cue = index.map { result.cues[$0] } ?? Cue(displayNumber: String(result.cues.count + additions.count + 1))
            if plan.matchMode == .source || index == nil {
                if let number = row.content.number { cue.displayNumber = number }
                if let speaker = row.content.speaker { cue.speaker = speaker }
                if let note = row.content.note { cue.note = note }
            }
            for (id, text) in row.content.texts {
                if id == result.languages.first?.id { cue.text = text } else { cue.translations[id] = text }
                // Source formatting is only applied when creating a cue. Re-import preserves production styling.
                if index == nil, let traits = row.content.traits[id] {
                    var patch = cue.styleOverrides[id] ?? TextStylePatch()
                    patch.bold = traits.bold; patch.italic = traits.italic; patch.underline = traits.underline
                    cue.styleOverrides[id] = patch
                }
            }
            if plan.matchMode == .source {
                cue.importOrigin = CueImportOrigin(sourceID: plan.source.id, key: row.key, baseline: row.content)
            }
            if let index { result.cues[index] = cue } else { additions.append(cue) }
        }
        let insertion = cueID.flatMap { id in result.cues.firstIndex { $0.id == id } }.map { $0 + 1 } ?? result.cues.count
        result.cues.insert(contentsOf: additions, at: insertion)
        if plan.matchMode == .source {
            if let index = result.importSources.firstIndex(where: { $0.id == plan.source.id }) { result.importSources[index] = plan.source }
            else { result.importSources.append(plan.source) }
        }
        try result.validate()
        return result
    }
}
