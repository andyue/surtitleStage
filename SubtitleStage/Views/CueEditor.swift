import SwiftUI
import AppKit
import SubtitleCore

struct CueEditor: View {
    @ObservedObject var store: ProjectStore
    let cue: Cue
    private func field<Value>(_ key: WritableKeyPath<Cue, Value>) -> Binding<Value> {
        Binding(get: { store.project.cues.first(where: { $0.id == cue.id })?[keyPath: key] ?? cue[keyPath: key] }, set: { value in
            guard var current = store.project.cues.first(where: { $0.id == cue.id }) else { return }
            current[keyPath: key] = value; store.editCue(current)
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cue Details / Typography").font(.headline)
            TextField("Number", text: field(\.displayNumber)).frame(width: 100)
            TextField("Notes", text: field(\.note), axis: .vertical).lineLimit(2...4)
            HStack { Text("Font"); FontSelector(selection: field(\.style.fontName)) }
            if NSFont(name: cue.style.fontName, size: cue.style.fontSize) == nil {
                Text("Font unavailable. Output uses the system fallback font.").foregroundStyle(.orange)
            }
            HStack {
                numeric("Size", key: \.style.fontSize, range: 1...2048)
                numeric("Character spacing", key: \.style.characterSpacing, range: -100...1000)
                numeric("Line spacing", key: \.style.lineSpacing, range: 0...2048)
            }
            Picker("Alignment", selection: field(\.style.alignment)) {
                ForEach(TextAlignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.segmented)
            Text("Editing changes the saved cue and updates live output immediately.")
                .font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder)
    }
    private func numeric(_ title: String, key: WritableKeyPath<Cue, Double>, range: ClosedRange<Double>) -> some View {
        let binding = field(key)
        return VStack(alignment: .leading) {
            Text(title).font(.caption)
            TextField(title, value: Binding(get: { binding.wrappedValue }, set: { if $0.isFinite { binding.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) } }), format: .number)
        }
    }
}
