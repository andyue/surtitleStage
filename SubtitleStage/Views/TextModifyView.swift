import SwiftUI
import AppKit
import SubtitleCore

struct TextModifyView: View {
    @ObservedObject var store: ProjectStore
    @State private var batchMessage: String?
    private var surtitleID: UUID? { store.selectedSurtitleID ?? store.project.languages.first?.id }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Surtitle", selection: Binding(get: { surtitleID }, set: { store.selectedSurtitleID = $0 })) {
                ForEach(store.project.languages) { Text($0.name).tag(Optional($0.id)) }
            }
            if let cue = store.selectedCue, let id = surtitleID {
                Text("Cue \(cue.displayNumber)").font(.headline)
                row("Font", property: .fontName, cue: cue, id: id) {
                    FontSelector(selection: binding(\.fontName, .fontName, cue: cue, id: id))
                }
                row("Size", property: .fontSize, cue: cue, id: id) {
                    NumericField(value: binding(\.fontSize, .fontSize, cue: cue, id: id), range: 1...2048).frame(width: 110)
                }
                row("Character spacing", property: .characterSpacing, cue: cue, id: id) {
                    NumericField(value: binding(\.characterSpacing, .characterSpacing, cue: cue, id: id), range: -100...1000).frame(width: 110)
                }
                row("Line spacing", property: .lineSpacing, cue: cue, id: id) {
                    NumericField(value: binding(\.lineSpacing, .lineSpacing, cue: cue, id: id), range: 0...2048).frame(width: 110)
                }
                row("Color", property: .color, cue: cue, id: id) {
                    ColorPicker("Color", selection: colorBinding(cue: cue, id: id), supportsOpacity: true).labelsHidden()
                }
                row("Bold", property: .bold, cue: cue, id: id) {
                    Toggle("Bold", isOn: binding(\.bold, .bold, cue: cue, id: id)).labelsHidden()
                }
                row("Italic", property: .italic, cue: cue, id: id) {
                    Toggle("Italic", isOn: binding(\.italic, .italic, cue: cue, id: id)).labelsHidden()
                }
                row("Underline", property: .underline, cue: cue, id: id) {
                    Toggle("Underline", isOn: binding(\.underline, .underline, cue: cue, id: id)).labelsHidden()
                }
                row("Strikethrough", property: .strikethrough, cue: cue, id: id) {
                    Toggle("Strikethrough", isOn: binding(\.strikethrough, .strikethrough, cue: cue, id: id)).labelsHidden()
                }
                row("Alignment", property: .alignment, cue: cue, id: id) {
                    Picker("Alignment", selection: binding(\.alignment, .alignment, cue: cue, id: id)) {
                        ForEach(TextAlignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                }
                GroupBox("Cue Fade") {
                    VStack(spacing: 10) {
                        HStack {
                            Toggle("Fade in when this cue goes live", isOn: transitionBinding(cue.id, \.fadeInEnabled))
                            Spacer()
                            NumericField(value: transitionBinding(cue.id, \.fadeInDuration), range: 0...10, step: 0.1)
                                .frame(width: 90).disabled(!currentCue(cue.id).transition.fadeInEnabled)
                        }
                        HStack {
                            Toggle("Fade out before leaving this cue", isOn: transitionBinding(cue.id, \.fadeOutEnabled))
                            Spacer()
                            NumericField(value: transitionBinding(cue.id, \.fadeOutDuration), range: 0...10, step: 0.1)
                                .frame(width: 90).disabled(!currentCue(cue.id).transition.fadeOutEnabled)
                        }
                    }.padding(4)
                }
                if let batchMessage { Text(batchMessage).font(.caption).foregroundStyle(.secondary) }
                Text("↑ / ↓ adjusts a focused number by 1. Batch applies only that property to all cues in this Surtitle column.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Changes update the live output immediately.")
                    .font(.caption).foregroundStyle(.green)
                let font = currentStyle(cue: cue, id: id).fontName
                if NSFont(name: font, size: 12) == nil { Text("Font unavailable: \(font). System fallback will be used.").foregroundStyle(.orange) }
            } else { ContentUnavailableView("Select a cue cell", systemImage: "textformat") }
        }
    }
    private func currentStyle(cue: Cue, id: UUID) -> TextStyle {
        store.textStyle(cue: store.project.cues.first(where: { $0.id == cue.id }) ?? cue, surtitleID: id)
    }
    private func currentCue(_ id: UUID) -> Cue {
        store.project.cues.first(where: { $0.id == id }) ?? Cue(id: id)
    }
    private func transitionBinding<Value>(_ cueID: UUID, _ key: WritableKeyPath<CueTransition, Value>) -> Binding<Value> {
        Binding(get: { currentCue(cueID).transition[keyPath: key] }, set: { value in
            store.editCueTransition(cueID) { $0[keyPath: key] = value }
        })
    }
    private func binding<Value>(_ key: WritableKeyPath<TextStyle, Value>, _ property: TextProperty, cue: Cue, id: UUID) -> Binding<Value> {
        Binding(get: { currentStyle(cue: cue, id: id)[keyPath: key] }, set: { value in
            var style = currentStyle(cue: cue, id: id); style[keyPath: key] = value
            store.modifyTextStyle(cueID: cue.id, surtitleID: id, property: property, style: style)
        })
    }
    private func colorBinding(cue: Cue, id: UUID) -> Binding<Color> {
        let binding = binding(\.color, .color, cue: cue, id: id)
        return Binding(get: {
            let c = binding.wrappedValue
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        }, set: { color in
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            binding.wrappedValue = TextColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
        })
    }
    private func row<Content: View>(_ name: String, property: TextProperty, cue: Cue, id: UUID, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text(name).frame(width: 118, alignment: .leading)
                content()
                Spacer(minLength: 4)
                Button("Batch") {
                    store.modifyTextStyle(cueID: cue.id, surtitleID: id, property: property, style: currentStyle(cue: cue, id: id), batch: true)
                    batchMessage = "\(name) applied to \(store.project.cues.count) cues."
                }.help("Apply \(name) to every cue in this Surtitle column")
            }.frame(minHeight: 28)
            Divider()
        }
    }
}
