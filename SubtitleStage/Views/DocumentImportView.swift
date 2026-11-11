import SwiftUI
import SubtitleCore

struct DocumentImportView: View {
    @ObservedObject var store: ProjectStore
    @StateObject private var session: DocumentImportSession
    @Environment(\.dismiss) private var dismiss
    @State private var showNewSurtitle = false
    @State private var newSurtitleColumn: Int?
    @State private var newSurtitleName = ""
    @State private var focused: UUID?
    @State private var checked: Set<UUID> = []
    @State private var start = "1"
    @State private var speaker = ""
    @State private var layer: UUID
    init(store: ProjectStore, request: DocumentImportRequest, preparedSession: DocumentImportSession? = nil) {
        self.store = store
        _session = StateObject(wrappedValue: preparedSession ?? DocumentImportSession(request: request, store: store))
        _layer = State(initialValue: store.project.languages[0].id)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.request.source == nil ? "Import Document" : "Re-import Document").font(.title2)
            Text(session.request.url.lastPathComponent).foregroundStyle(.secondary)
            if session.plan == nil {
                Picker("Import mode", selection: $session.matchMode) {
                    Text(session.request.source == nil ? "Add New Cues" : "Update by Source ID").tag(ImportMatchMode.source)
                    Text("Merge by Cue Number").tag(ImportMatchMode.cueNumber)
                }.disabled(session.busy)
                if session.matchMode == .cueNumber {
                    Text("Map Cue Number and the target Surtitle text. Matching numbers share one cue; only mapped text is updated. Missing numbers create new cues. Existing text replacements require confirmation. 001 and 1 are different numbers.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = session.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if session.busy { ProgressView("Preparing import…") }
            if let parsed = session.parsed {
                if !parsed.warnings.isEmpty {
                    DisclosureGroup("Document warnings (\(parsed.warnings.count))") {
                        ScrollView { Text(parsed.warnings.joined(separator: "\n")).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 90)
                    }
                }
                if let plan = session.plan { difference(plan) }
                else if !session.hasPreview && !parsed.sheets.isEmpty { mapping(parsed) }
                else { workspace }
            } else { Spacer() }
            HStack {
                Button("Cancel") { session.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if session.plan != nil {
                    Button("Back to Workspace") { session.plan = nil }
                    Button("Apply Checked Changes (\(session.selectedKeys.count))") { session.apply(store: store) { dismiss() } }
                        .disabled(session.selectedKeys.isEmpty)
                } else if session.hasPreview {
                    if session.parsed?.sheets.isEmpty == false {
                        Button("Back to Mapping") { session.hasPreview = false; session.rows = []; checked = []; focused = nil }
                    }
                    Button("Review Changes") { session.review() }
                }
            }.disabled(session.busy)
        }.padding(20).frame(width: 1040, height: 740)
            .alert("New Surtitle", isPresented: $showNewSurtitle) {
                TextField("Surtitle name", text: $newSurtitleName)
                Button("Cancel", role: .cancel) { newSurtitleColumn = nil }
                Button("Create") {
                    guard let column = newSurtitleColumn else { return }
                    edit { _ = try session.addSurtitle(name: newSurtitleName, column: column) }
                    newSurtitleColumn = nil
                }
            } message: { Text("Created with this import only after Apply. Canceling the import leaves your show unchanged.") }
            .task { if session.parsed == nil { session.load() } }.onDisappear { session.cancel() }
    }
    private func mapping(_ parsed: ParsedDocument) -> some View {
        VStack(alignment: .leading) {
            Picker("Worksheet", selection: $session.configuration.sheet) {
                ForEach(parsed.sheets) { Text($0.name).tag($0.name) }
            }.onChange(of: session.configuration.sheet) { _, name in
                if session.request.source == nil {
                    session.configuration.columns = [:]
                    session.configuration.headerRow = parsed.sheets.first { $0.name == name }?.suggestedHeader ?? 0
                }
            }
            TextField("Header row (0 = no header)", value: $session.configuration.headerRow, format: .number)
            Picker("Default Surtitle for Dialogue", selection: $session.configuration.defaultLayerID) {
                ForEach(session.languages) { Text($0.name).tag($0.id) }
            }
            Text("Map text columns to the desired Surtitles. Merge by Cue Number requires a Cue number column; source ID is optional. Update by Source ID uses stable external IDs. Target routes Dialogue to a Surtitle name or UUID.")
                .font(.caption).foregroundStyle(.secondary)
            if let sheet = parsed.sheets.first(where: { $0.name == session.configuration.sheet }) {
                List(0..<sheet.columnCount, id: \.self) { column in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Column \(column + 1): \(sheet.rows.first { $0.number == session.configuration.headerRow }?.cells[column] ?? "(no header)")")
                            Text(sheet.rows.filter { $0.number > session.configuration.headerRow }.prefix(3).compactMap { $0.cells[column] }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Picker("Map to", selection: Binding(get: { roleName(session.configuration.columns[column] ?? .ignore) },
                                                           set: { value in
                                                               if value == "new-surtitle" {
                                                                   let header = sheet.rows.first { $0.number == session.configuration.headerRow }?.cells[column] ?? ""
                                                                   newSurtitleName = header.isEmpty ? "Surtitle \(session.languages.count + 1)" : header
                                                                   newSurtitleColumn = column
                                                                   showNewSurtitle = true
                                                               } else { session.configuration.columns[column] = roleValue(value) }
                                                           })) {
                            Text("Ignore").tag("ignore")
                            Text("Stable source ID").tag("key")
                            Text("Cue number").tag("number")
                            Text("Speaker / Character").tag("speaker")
                            Text("Notes").tag("note")
                            Text("Target").tag("target")
                            Text("Dialogue").tag("dialogue")
                            ForEach(session.languages) { Text("Text → " + $0.name).tag($0.id.uuidString) }
                            Divider()
                            Text("New Surtitle…").tag("new-surtitle")
                        }.frame(width: 290)
                    }
                }
                if !session.draftLanguages.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            Text("Create on Apply:")
                            ForEach(session.draftLanguages) { language in
                                Button { session.removeDraftSurtitle(language.id) } label: {
                                    Label(language.name, systemImage: "xmark.circle")
                                }.help("Remove this planned Surtitle and its column mapping")
                            }
                        }
                    }.frame(height: 30)
                }
                Button("Build Preview") { session.map() }.disabled(session.busy)
            }
        }.disabled(session.busy)
    }
    private var workspace: some View {
        VStack(alignment: .leading) {
            Text("Preview only — project and playback remain unchanged until Apply. Checked rows are used by editing actions; Ignore excludes a row from import.").font(.caption)
            HStack {
                Button("Check All") { checked = Set(session.rows.map(\.id)) }
                Button("Clear") { checked = [] }
                Button("Split Lines") { edit {
                    guard let id = focused, let index = session.rows.firstIndex(where: { $0.id == id }) else { return }
                    let parts = try ImportWorkspaceEditing.split(session.rows[index])
                    session.rows.replaceSubrange(index...index, with: parts); focused = parts.first?.id; checked = []
                } }
                Button("Merge Checked") { edit {
                    let indices = session.rows.indices.filter { checked.contains(session.rows[$0].id) }
                    guard let first = indices.first, let last = indices.last, indices.count > 1, last - first + 1 == indices.count else {
                        throw ProjectError.invalid("Check at least two adjacent rows to merge.")
                    }
                    let row = try ImportWorkspaceEditing.merge(indices.map { session.rows[$0] })
                    session.rows.replaceSubrange(first...last, with: [row]); focused = row.id; checked = []
                } }
                TextField("Start", text: $start).frame(width: 60)
                Button("Renumber Checked") { edit {
                    let count = session.rows.filter { checked.contains($0.id) }.count
                    guard let number = Int(start), number >= 0, number <= Int.max - count else { throw ProjectError.invalid("Enter a valid starting number.") }
                    var next = number
                    for i in session.rows.indices where checked.contains(session.rows[i].id) { session.rows[i].content.number = String(next); next += 1 }
                } }
            }
            HStack {
                TextField("Speaker", text: $speaker)
                Button("Assign Speaker to Checked") {
                    for i in session.rows.indices where checked.contains(session.rows[i].id) { session.rows[i].content.speaker = speaker }
                }
                Picker("Surtitle", selection: $layer) { ForEach(session.languages) { Text($0.name).tag($0.id) } }
                Button("Assign Layer to Checked") { edit {
                    let indices = session.rows.indices.filter { checked.contains(session.rows[$0].id) }
                    guard indices.allSatisfy({ session.rows[$0].content.texts.count == 1 }) else {
                        throw ProjectError.invalid("Layer reassignment requires single-language rows. Edit multilingual columns individually.")
                    }
                    for i in indices {
                        let content = session.rows[i].content
                        session.rows[i].content.texts = [layer: content.texts.values.first ?? ""]
                        session.rows[i].content.traits = content.traits.values.first.map { [layer: $0] } ?? [:]
                    }
                } }
            }
            HSplitView {
                List(selection: $focused) {
                    ForEach(session.rows) { row in
                        HStack {
                            Toggle("Check", isOn: Binding(get: { checked.contains(row.id) }, set: { if $0 { checked.insert(row.id) } else { checked.remove(row.id) } })).labelsHidden()
                            VStack(alignment: .leading) {
                                Text("\(row.ignored ? "IGNORE · " : "")\(row.content.number ?? "") \(row.content.speaker ?? "") · \(row.location)").font(.caption)
                                Text(session.languages.compactMap { row.content.texts[$0.id] }.joined(separator: " / ")).lineLimit(2)
                            }
                        }.tag(row.id)
                    }
                }.frame(minWidth: 340)
                if let index = session.rows.firstIndex(where: { $0.id == focused }) {
                    rowEditor(index).frame(minWidth: 400)
                } else { Text("Select a row to edit its content.").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }.disabled(session.busy)
    }
    private func rowEditor(_ index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading) {
                Toggle("Ignore this row", isOn: $session.rows[index].ignored)
                TextField("Source key", text: $session.rows[index].key)
                TextField("Cue number", text: optional(index, \.number))
                TextField("Speaker", text: optional(index, \.speaker))
                TextField("Notes", text: optional(index, \.note), axis: .vertical)
                ForEach(session.languages.filter { session.rows[index].content.texts[$0.id] != nil }) { language in
                    Text(language.name).font(.headline)
                    TextEditor(text: Binding(get: { session.rows[index].content.texts[language.id] ?? "" }, set: { session.rows[index].content.texts[language.id] = $0 }))
                        .frame(height: 110).border(.secondary)
                }
                ForEach(session.rows[index].warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }.padding(8).textFieldStyle(.roundedBorder)
        }.id(session.rows[index].id)
    }
    private func difference(_ plan: ImportPlan) -> some View {
        VStack(alignment: .leading) {
            if !session.draftLanguages.isEmpty {
                Text("New Surtitles on Apply: " + session.draftLanguages.map(\.name).joined(separator: ", ")).font(.headline)
                Text("New Surtitles start at the default subtitle position. Adjust Layout after importing.").font(.caption)
            }
            Text(plan.matchMode == .cueNumber
                 ? "Matching numbers update only the mapped Surtitle text. Other languages, metadata, source bindings, UUIDs and settings are preserved. No cues are deleted. Check replacements explicitly."
                 : "Existing cue order, UUIDs, formatting, layout and transitions are preserved. New cues are inserted after the selected cue. Deletions and local-edit conflicts require explicit selection.").font(.caption)
            List(plan.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("\(item.change.rawValue) · \(plan.matchMode == .cueNumber ? "Cue " + (item.incoming?.content.number ?? "") : item.key)\(item.conflict ? (plan.matchMode == .cueNumber ? " · REPLACE EXISTING TEXT" : " · OVERWRITE LOCAL EDITS") : "")",
                           isOn: Binding(get: { session.selectedKeys.contains(item.key) }, set: { if $0 { session.selectedKeys.insert(item.key) } else { session.selectedKeys.remove(item.key) } }))
                        .disabled(item.change == .unchanged)
                    Text(item.detail).font(.caption).foregroundStyle(item.conflict ? .orange : .secondary)
                    HStack(alignment: .top) {
                        if let cue = session.baseline.cues.first(where: { $0.id == item.cueID }) {
                            VStack(alignment: .leading) {
                                Text("Current").bold()
                                Text("Number: \(cue.displayNumber) · Speaker: \(cue.speaker)\nNotes: \(cue.note)")
                                ForEach(session.languages) { language in
                                    Text(language.name + ": " + session.baseline.text(for: cue, languageID: language.id))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let incoming = item.incoming {
                            VStack(alignment: .leading) {
                                Text("Incoming").bold()
                                Text("Number: \(incoming.content.number ?? "(preserved)") · Speaker: \(incoming.content.speaker ?? "(preserved)")\nNotes: \(incoming.content.note ?? "(preserved)")")
                                ForEach(session.languages.filter { incoming.content.texts[$0.id] != nil }) { language in
                                    Text(language.name + ": " + (incoming.content.texts[language.id] ?? ""))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.font(.caption).textSelection(.enabled)
                }.padding(.vertical, 5)
            }
        }.disabled(session.busy)
    }
    private func optional(_ index: Int, _ key: WritableKeyPath<ImportedContent, String?>) -> Binding<String> {
        Binding(get: { session.rows[index].content[keyPath: key] ?? "" }, set: { session.rows[index].content[keyPath: key] = $0 })
    }
    private func edit(_ operation: () throws -> Void) {
        do { try operation(); session.error = nil } catch { session.error = error.localizedDescription }
    }
    private func roleName(_ role: ImportColumn) -> String {
        switch role {
        case .ignore: "ignore"; case .key: "key"; case .number: "number"; case .speaker: "speaker"
        case .note: "note"; case .target: "target"; case .dialogue: "dialogue"; case .text(let id): id.uuidString
        }
    }
    private func roleValue(_ value: String) -> ImportColumn {
        switch value {
        case "key": .key; case "number": .number; case "speaker": .speaker; case "note": .note
        case "target": .target; case "dialogue": .dialogue
        default: UUID(uuidString: value).map(ImportColumn.text) ?? .ignore
        }
    }
}
