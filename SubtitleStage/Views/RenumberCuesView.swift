import SwiftUI
import SubtitleCore

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
