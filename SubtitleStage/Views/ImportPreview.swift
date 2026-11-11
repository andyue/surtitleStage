import SwiftUI
import SubtitleCore

struct ImportPreview: View {
    @ObservedObject var store: ProjectStore
    let source: String
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ClipboardMode = .line
    @State private var items: [ImportItem] = []
    @State private var parsing = true
    @State private var targetSurtitleID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste As Cues").font(.title2)
            Picker("Split by", selection: $mode) {
                Text("Line").tag(ClipboardMode.line)
                Text("Paragraph").tag(ClipboardMode.paragraph)
            }.pickerStyle(.segmented)
            Picker("Paste into", selection: Binding(get: { targetSurtitleID ?? store.selectedSurtitleID ?? store.project.languages.first?.id }, set: { targetSurtitleID = $0 })) {
                ForEach(store.project.languages) { Text($0.name).tag(Optional($0.id)) }
            }
            if parsing { ProgressView("Parsing clipboard…") }
            List(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top) { Text("\(index + 1)").foregroundStyle(.secondary); Text(item.text) }
            }
            HStack {
                Text(insertionDescription)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import") {
                    if let target = targetSurtitleID ?? store.selectedSurtitleID ?? store.project.languages.first?.id {
                        store.importItems(items, to: target, after: store.playback.selectedCueID)
                    }
                    dismiss()
                }.disabled(parsing || items.isEmpty)
            }
        }.padding(20).frame(width: 580, height: 480)
            .task(id: mode) {
                parsing = true
                let selectedMode = mode
                let parsed = await Task.detached { ClipboardImporter.parse(source, mode: selectedMode) }.value
                guard !Task.isCancelled else { return }
                items = parsed; parsing = false
            }
    }
    private var insertionDescription: String {
        if let cue = store.selectedCue {
            return "\(items.count) cues will be inserted below Cue \(cue.displayNumber)."
        }
        return "\(items.count) cues will be appended."
    }
}
