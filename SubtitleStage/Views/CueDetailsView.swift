import SwiftUI
import SubtitleCore

struct CueDetailsView: View {
    @ObservedObject var store: ProjectStore
    @FocusState private var focusedField: String?

    var body: some View {
        if let cue = store.selectedCue {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Number", text: binding(cue.id, \.displayNumber)).focused($focusedField, equals: "number")
                TextField("Name", text: binding(cue.id, \.name)).focused($focusedField, equals: "name")
                TextField("Speaker", text: binding(cue.id, \.speaker)).focused($focusedField, equals: "speaker")
                TextField("Notes", text: binding(cue.id, \.note), axis: .vertical)
                    .lineLimit(3...8).focused($focusedField, equals: "notes")
                Text("Editing cue details does not take a cue live.").font(.caption).foregroundStyle(.secondary)
            }.textFieldStyle(.roundedBorder)
                .onChange(of: focusedField) { _, _ in store.endHistoryGroup() }
                .onDisappear { store.endHistoryGroup() }
        } else {
            Text("Select a cue to edit its details.").foregroundStyle(.secondary)
        }
    }

    private func binding(_ id: UUID, _ key: WritableKeyPath<Cue, String>) -> Binding<String> {
        Binding(get: { store.project.cues.first { $0.id == id }?[keyPath: key] ?? "" },
                set: { store.editCueDetail(id, key: key, value: $0) })
    }
}

struct RenumberCuesView: View {
    @ObservedObject var store: ProjectStore
    let ids: Set<UUID>
    @State private var start = "1"
    @Environment(\.dismiss) private var dismiss

    private var preview: [CueNumberPreview]? {
        guard let value = Int(start) else { return nil }
        return store.numberPreview(ids: ids, start: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Renumber \(ids.count) checked cues").font(.headline)
            TextField("Starting number", text: $start).textFieldStyle(.roundedBorder)
            Text("Uses cue-list order. Other cues keep their numbers; duplicate display numbers are allowed.")
                .font(.caption).foregroundStyle(.secondary)
            if let preview {
                List(preview) { row in
                    HStack {
                        Text(row.oldNumber.isEmpty ? "—" : row.oldNumber)
                        Image(systemName: "arrow.right")
                        Text(row.newNumber)
                    }
                }
            } else {
                Text("Enter a non-negative whole number within range.").foregroundStyle(.orange)
                Spacer()
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") {
                    guard let value = Int(start) else { return }
                    store.renumberCues(ids: ids, start: value)
                    dismiss()
                }.disabled(preview == nil)
            }
        }.padding(20).frame(width: 460, height: 420)
    }
}
