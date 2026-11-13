import SwiftUI
import SubtitleCore

/// Mapping and the final preview stay on one page. Import is the only mutation.
struct DocumentImportView: View {
    @ObservedObject var store: ProjectStore
    @StateObject private var session: DocumentImportSession
    @Environment(\.dismiss) private var dismiss
    init(store: ProjectStore, request: DocumentImportRequest, preparedSession: DocumentImportSession? = nil) {
        self.store = store
        _session = StateObject(wrappedValue: preparedSession ?? DocumentImportSession(request: request, store: store))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.request.source == nil ? "Import Document" : "Re-import Document").font(.title2)
            HStack(alignment: .top) {
                Text(session.request.url.lastPathComponent).foregroundStyle(.secondary)
                Spacer()
                if let parsed = session.parsed, !parsed.warnings.isEmpty {
                    DisclosureGroup("Import notes (\(parsed.warnings.count))") {
                        ScrollView { Text(parsed.warnings.joined(separator: "\n")).font(.caption) }.frame(maxHeight: 90)
                    }.frame(maxWidth: 380)
                }
            }
            Text("Subtitle columns are created automatically using the original names. Click Import to finish on this page.").font(.caption)
            if !session.baseline.cues.isEmpty {
                Picker("Insert new cues", selection: $session.insertionAfterCueID) {
                    Text("At the end").tag(nil as UUID?)
                    ForEach(Array(session.baseline.cues.enumerated()), id: \.element.id) { index, cue in
                        Text("After Cue \(cue.displayNumber) · row \(index + 1)").tag(Optional(cue.id))
                    }
                }.disabled(session.busy)
            }
            if let error = session.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if session.busy { ProgressView("Preparing preview…") }
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let parsed = session.parsed, !parsed.sheets.isEmpty {
                            if parsed.sheets.count > 1 {
                                Picker("Worksheet", selection: $session.configuration.sheet) {
                                    ForEach(parsed.sheets) { Text($0.name).tag($0.name) }
                                }.onChange(of: session.configuration.sheet) { _ in
                                    if session.request.source == nil {
                                        session.configuration.headerRow = session.selectedSheet?.suggestedHeader ?? 0
                                        session.suggestColumns()
                                    }
                                    session.updatePreview()
                                }
                            }
                            if parsed.kind == "xlsx" {
                                TextField("Header row (0 = no header)", value: $session.configuration.headerRow, format: .number)
                                    .onChange(of: session.configuration.headerRow) { _ in session.suggestColumns(); session.updatePreview() }
                            }
                            ForEach(session.textColumns, id: \.self) { column in
                                let layer = session.languages.first { session.configuration.columns[column] == .text($0.id) }
                                HStack {
                                    Text(session.columnTitle(column)).font(.headline)
                                    Spacer()
                                    Text(layer?.name ?? "Not imported").foregroundStyle(.secondary)
                                }
                            }
                        }
                        if session.parsed?.sheets.isEmpty == true {
                            Picker("Surtitle", selection: $session.configuration.defaultLayerID) {
                                ForEach(session.languages) { Text($0.name).tag($0.id) }
                            }.onChange(of: session.configuration.defaultLayerID) { _ in session.updatePreview() }
                        }
                        Toggle("Include blank / disabled cues", isOn: $session.includeSkipped)
                            .onChange(of: session.includeSkipped) { _ in session.updatePreview() }
                        Text("Source IDs and cue numbers are handled automatically. Existing project data stays unchanged until Import.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }.frame(minWidth: 260, idealWidth: 300, maxWidth: 340).disabled(session.busy)
                if let plan = session.plan {
                    List(plan.items) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("Import cue", isOn: Binding(get: { session.selectedKeys.contains(item.key) }, set: {
                                if $0 { session.selectedKeys.insert(item.key) } else { session.selectedKeys.remove(item.key) }
                            })).labelsHidden().disabled(item.change == .unchanged || session.busy)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(item.incoming?.content.number ?? "") · \(item.change.rawValue)").font(.caption).foregroundStyle(.secondary)
                                if let row = item.incoming {
                                    ForEach(session.languages.filter { row.content.texts[$0.id] != nil }) { language in
                                        Text(language.name + ": " + (row.content.texts[language.id] ?? "")).lineLimit(3)
                                    }
                                }
                                if item.conflict || item.change == .deleted {
                                    Text(item.conflict ? "Replaces existing text — check only if intended." : "Deletes an existing cue — unchecked by default.")
                                        .font(.caption).foregroundStyle(.orange)
                                    Text(item.detail).font(.caption)
                                }
                            }
                        }.padding(.vertical, 3)
                    }.frame(minWidth: 450)
                } else { Text("Preview will appear here.").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            HStack {
                Button("Cancel") { session.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(session.selectedKeys.count) selected · \(session.rows.filter(\.ignored).count) skipped").font(.caption)
                Button("Import") { session.apply(store: store) { dismiss() } }
                    .disabled(session.busy || session.plan == nil || session.selectedKeys.isEmpty)
            }
        }.padding(20).frame(width: 1040, height: 740)
            .task { if session.parsed == nil { session.load() } }
            .onDisappear { session.cancel() }
    }
}
