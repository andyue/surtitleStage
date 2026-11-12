import SwiftUI
import SubtitleCore

struct ShowControlsView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var output: OutputManager
    @State private var showHotkeys = false
    var body: some View {
        GroupBox("Show Controls") {
            VStack(spacing: 8) {
                HStack {
                    Text("Opacity")
                    Spacer()
                    Button { store.adjustMasterOpacity(by: -0.05) } label: { Image(systemName: "minus") }
                        .disabled(store.playback.masterOpacity <= 0)
                    Text("\(Int((store.playback.masterOpacity * 100).rounded()))%")
                        .monospacedDigit().frame(width: 48)
                    Button { store.adjustMasterOpacity(by: 0.05) } label: { Image(systemName: "plus") }
                        .disabled(store.playback.masterOpacity >= 1)
                }
                HStack { Text("Blackout fade"); Spacer(); durationField(\.blackoutFadeDuration) }
                Divider()
                HStack(spacing: 8) {
                    Button(action: store.previous) { Text("Previous").frame(maxWidth: .infinity, minHeight: 30) }.tint(.blue).disabled(store.isCueTransitioning)
                    Button(action: store.go) { Text("GO / Next").frame(maxWidth: .infinity, minHeight: 30) }.tint(.green).disabled(store.isCueTransitioning)
                    Button { store.toggleBlackout() } label: {
                        Text(store.playback.isBlackout ? "Restore" : "Blackout").frame(maxWidth: .infinity, minHeight: 30)
                    }.tint(.red)
                }.buttonStyle(.borderedProminent)
                HStack(spacing: 8) {
                    Button { output.startConfigured(store: store) } label: { Text("Start Output").frame(maxWidth: .infinity, minHeight: 28) }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .disabled(store.project.outputs.allSatisfy { !$0.isEnabled || $0.displayID == nil } || store.isBusy)
                    Button("Stop Output") { output.stopAll() }.disabled(output.activeDisplayIDs.isEmpty)
                }
                if let status = output.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Text(store.showControlsFocused ? "Hotkeys active" : "Click here to focus Show Controls")
                        .font(.caption).foregroundStyle(store.showControlsFocused ? .green : .secondary)
                    Spacer()
                    Button("Hotkeys…") { showHotkeys = true }
                }
            }.padding(4)
        }
        .sheet(isPresented: $showHotkeys) { HotkeySettingsView(settings: store.hotkeys) }
        .disabled(store.isBusy)
        .background(ShowControlsFocus(store: store))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(store.showControlsFocused ? Color.accentColor : .clear, lineWidth: 2).allowsHitTesting(false))
    }
    private func durationField(_ keyPath: WritableKeyPath<TransitionSettings, Double>) -> some View {
        NumericField(value: Binding(get: { store.project.transitions[keyPath: keyPath] }, set: { value in
            store.change { $0.transitions[keyPath: keyPath] = min(10, max(0, value)) }
        }), range: 0...10, step: 0.1)
        .frame(width: 82)
    }
}
