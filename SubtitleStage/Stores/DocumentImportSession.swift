import Foundation
import SwiftUI
import SubtitleCore

struct DocumentImportRequest: Identifiable {
    let id = UUID()
    let url: URL
    var source: ImportSource?
}

@MainActor
final class DocumentImportSession: ObservableObject {
    @Published var includeSkipped = false
    private var importedPrimaryName: String?
    @Published var draftLanguages: [LanguageLayer] = []
    @Published var matchMode: ImportMatchMode
    @Published var hasPreview = false
    @Published var parsed: ParsedDocument?
    @Published var configuration: ImportConfiguration
    @Published var rows: [DocumentImportRow] = []
    @Published var plan: ImportPlan?
    @Published var selectedKeys: Set<String> = []
    @Published var busy = false
    @Published var error: String?
    let request: DocumentImportRequest
    let baseline: Project
    let sessionID: UUID
    private var task: Task<Void, Never>?

    init(request: DocumentImportRequest, store: ProjectStore) {
        self.request = request; baseline = store.project; sessionID = store.sessionID
        matchMode = .source
        configuration = request.source?.configuration ?? ImportConfiguration(defaultLayerID: store.project.languages[0].id)
    }
    var languages: [LanguageLayer] {
        var result = baseline.languages + draftLanguages
        if let importedPrimaryName { result[0].name = importedPrimaryName }
        return result
    }
    var importProject: Project {
        var project = baseline
        let used = Set(configuration.columns.values.compactMap { role -> UUID? in
            if case .text(let id) = role { return id }; return nil
        })
        let additions = draftLanguages.filter { used.contains($0.id) }
        project.languages += additions
        if let importedPrimaryName { project.languages[0].name = importedPrimaryName }
        for i in project.outputs.indices {
            for language in additions { project.outputs[i].languageLayouts[language.id] = LanguagePlacement(language) }
        }
        return project
    }
    @discardableResult
    func addSurtitle(name: String, column: Int) throws -> UUID {
        guard !busy, plan == nil else { throw ProjectError.invalid("Return to mapping before adding a Surtitle.") }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !languages.contains(where: { $0.name == name }) else {
            throw ProjectError.invalid("Enter a non-empty, unique Surtitle name.")
        }
        let canvas = baseline.canvas
        let language = LanguageLayer(name: name, frame: PixelFrame(x: canvas.width * 0.05, y: canvas.height * 0.65,
                                                                   width: max(1, canvas.width * 0.9), height: max(1, canvas.height * 0.2)))
        draftLanguages.append(language)
        configuration.columns[column] = .text(language.id)
        return language.id
    }
    func removeDraftSurtitle(_ id: UUID) {
        guard !busy, plan == nil, !hasPreview else { return }
        draftLanguages.removeAll { $0.id == id }
        configuration.columns = configuration.columns.filter { $0.value != .text(id) }
        if configuration.defaultLayerID == id { configuration.defaultLayerID = baseline.languages[0].id }
    }
    func cancel() { task?.cancel() }
    func load() {
        let url = request.url, layer = configuration.defaultLayerID
        perform {
            let document = try await importBackground { try OfficeDocumentImporter.parse(url: url, defaultLayerID: layer) }
            self.parsed = document
            self.rows = document.rows
            if self.request.source == nil, let sheet = document.sheets.first {
                self.configuration.sheet = sheet.name
                self.configuration.headerRow = document.kind == "glypheo" ? 1 : sheet.suggestedHeader
                self.suggestColumns()
            }
            if document.kind == "glypheo" { self.configuration.columns[2] = .ignore }
            try await self.buildSinglePagePreview()

        }
    }
    var selectedSheet: SpreadsheetSheet? { parsed?.sheets.first { $0.name == configuration.sheet } }
    var textColumns: [Int] {
        guard let sheet = selectedSheet else { return [] }
        return (0..<sheet.columnCount).filter { column in
            if parsed?.kind == "glypheo" { return column >= 3 }
            let name = columnTitle(column).lowercased().replacingOccurrences(of: " ", with: "")
            if ["notes", "note", "備註", "group/status", "speaker", "character", "角色"].contains(name) { return false }
            switch configuration.columns[column] {
            case .key, .number, .speaker, .note, .target: return false
            default: return true
            }
        }
    }
    func columnTitle(_ column: Int) -> String {
        selectedSheet?.rows.first { $0.number == configuration.headerRow }?.cells[column] ?? "Column \(column + 1)"
    }
    func suggestColumns() {
        guard let sheet = selectedSheet else { return }
        draftLanguages = []; importedPrimaryName = nil; configuration.columns = [:]
        var used = Set<UUID>()
        for column in 0..<sheet.columnCount {
            if parsed?.kind == "glypheo", column < 3 {
                configuration.columns[column] = column == 0 ? .key : column == 1 ? .number : .ignore
                continue
            }
            let title = columnTitle(column).replacingOccurrences(of: "^Text [0-9]+: ", with: "", options: .regularExpression)
            let normalized = title.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
            if ["sourceid", "id", "stableid", "來源id"].contains(normalized), !configuration.columns.values.contains(.key) { configuration.columns[column] = .key; continue }
            if ["cuenumber", "cue", "number", "編號"].contains(normalized), !configuration.columns.values.contains(.number) { configuration.columns[column] = .number; continue }
            if ["notes", "note", "備註", "group/status", "speaker", "character", "角色"].contains(normalized) { configuration.columns[column] = .ignore; continue }
            if let existing = languages.first(where: { $0.name == title && !used.contains($0.id) }) {
                configuration.columns[column] = .text(existing.id); used.insert(existing.id)
            } else if baseline.cues.isEmpty, baseline.languages.count == 1, used.isEmpty {
                let id = baseline.languages[0].id
                importedPrimaryName = title
                configuration.columns[column] = .text(id); used.insert(id)
            } else {
                let canvas = baseline.canvas
                var name = title; var suffix = 2
                while languages.contains(where: { $0.name == name }) { name = title + " \(suffix)"; suffix += 1 }
                let layer = LanguageLayer(name: name, frame: PixelFrame(x: canvas.width * 0.05, y: canvas.height * 0.65, width: max(1, canvas.width * 0.9), height: max(1, canvas.height * 0.2)))
                draftLanguages.append(layer); used.insert(layer.id); configuration.columns[column] = .text(layer.id)
            }
        }
    }
    func updatePreview() {
        plan = nil; selectedKeys = []
        perform { try await self.buildSinglePagePreview() }
    }
    private func buildSinglePagePreview() async throws {
        let config = configuration, languages = languages, sheet = selectedSheet
        let documentRows = parsed?.rows ?? [], includeSkipped = includeSkipped
        let mapped = try await importBackground {
            var rows = try sheet.map { try ImportMapping.rows(sheet: $0, configuration: config, languages: languages) } ?? documentRows
            if sheet == nil {
                for i in rows.indices where rows[i].content.texts.count == 1 {
                    rows[i].content.texts = [config.defaultLayerID: rows[i].content.texts.values.first ?? ""]
                    if let traits = rows[i].content.traits.values.first { rows[i].content.traits = [config.defaultLayerID: traits] }
                }
            }
            if includeSkipped { for i in rows.indices { rows[i].ignored = false } }
            return rows
        }
        let project = importProject, mode = matchMode, reimport = request.source != nil
        var source = request.source ?? ImportSource(name: request.url.lastPathComponent, kind: parsed?.kind ?? "", configuration: config, hasStableKeys: false)
        source.configuration = config
        source.hasStableKeys = config.columns.values.contains(.key) && ["xlsx", "glypheo"].contains(parsed?.kind ?? "")
        let prepared = source
        let result = try await importBackground { try ImportDiff.plan(project: project, source: prepared, rows: mapped, reimport: reimport, matchMode: mode) }
        rows = mapped; plan = result; hasPreview = true
        selectedKeys = Set(result.items.filter { ($0.change == .new || $0.change == .modified) && !$0.conflict }.map(\.key))
    }
    func map() {
        guard let sheet = parsed?.sheets.first(where: { $0.name == configuration.sheet }) else { error = "Select a worksheet."; return }
        let config = configuration, languages = languages
        perform {
            self.rows = try await importBackground { try ImportMapping.rows(sheet: sheet, configuration: config, languages: languages) }
            self.hasPreview = true
        }
    }
    func review() {
        let project = importProject, rows = rows, reimport = request.source != nil, mode = matchMode
        var source = request.source ?? ImportSource(name: request.url.lastPathComponent, kind: parsed?.kind ?? "", configuration: configuration, hasStableKeys: false)
        source.configuration = configuration
        source.hasStableKeys = configuration.columns.values.contains(.key) && ["xlsx", "glypheo"].contains(parsed?.kind ?? "")
        let preparedSource = source
        perform {
            let plan = try await importBackground { try ImportDiff.plan(project: project, source: preparedSource, rows: rows, reimport: reimport, matchMode: mode) }
            self.plan = plan
            self.selectedKeys = Set(plan.items.filter { ($0.change == .new || $0.change == .modified) && !$0.conflict }.map(\.key))
        }
    }
    func apply(store: ProjectStore, completion: @escaping () -> Void) {
        guard let plan else { return }
        let keys = selectedKeys, project = importProject, after = store.playback.selectedCueID, live = store.playback.liveCueID
        perform {
            let result = try await importBackground { try ImportDiff.applying(plan, selectedKeys: keys, to: project, after: after, liveCueID: live) }
            try store.commitImport(result, baseline: self.baseline, sessionID: self.sessionID,
                                   affected: Set(plan.items.filter { keys.contains($0.key) && $0.change != .unchanged }.compactMap(\.cueID)))
            completion()
        }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil
        task = Task {
            defer { busy = false }
            do { try Task.checkCancellation(); try await operation() }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
extension ProjectStore {
    func commitImport(_ result: Project, baseline: Project, sessionID: UUID, affected: Set<UUID>) throws {
        try Task.checkCancellation()
        guard self.sessionID == sessionID, project == baseline, !isBusy, !isCueTransitioning else {
            throw ProjectError.invalid("The project changed while previewing. Close and reopen the import to review the latest project. Nothing was applied.")
        }
        guard playback.liveCueID.map({ !affected.contains($0) }) ?? true else {
            throw ProjectError.invalid("A selected change now affects the live cue. Nothing was applied.")
        }
        change { $0 = result }
        if let id = playback.selectedCueID, !project.cues.contains(where: { $0.id == id }) {
            playback.selectedCueID = project.cues.first?.id
        }
    }
}

/// Cancellation follows the sheet lifetime through background parsing and diff work.
private func importBackground<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
    let worker = Task.detached(priority: .userInitiated, operation: operation)
    return try await withTaskCancellationHandler {
        let value = try await worker.value
        try Task.checkCancellation()
        return value
    } onCancel: { worker.cancel() }
}
