import AppKit
import SwiftUI
import SubtitleCore

struct HotkeySettingsView: View {
    @ObservedObject var settings: HotkeySettings
    @Environment(\.dismiss) private var dismiss
    @State private var recording: PlaybackShortcut?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Show Control Hotkeys").font(.title2)
            Text("Hotkeys work only while Show Controls has keyboard focus. Text editing, IME and dialogs always take priority. Assignments are saved on this Mac.")
                .foregroundStyle(.secondary)
            ForEach(PlaybackShortcut.allCases, id: \.self) { action in
                HStack {
                    Text(action.title).frame(width: 180, alignment: .leading)
                    Text(settings.configuration.bindings[action]?.label ?? "Unassigned").frame(width: 110)
                    Button(recording == action ? "Listening…" : "Assign…") { recording = action }
                    Button("Clear") { settings.assign(nil, to: action); recording = nil }
                        .disabled(settings.configuration.bindings[action] == nil)
                }
            }
            if let action = recording {
                Text("Press a key for \(action.title). Shift / Control / Option are supported; Command is reserved for menus.").font(.caption)
                HotkeyRecorder { event in
                    guard !event.isARepeat else { return }
                    guard let chord = HotkeySettings.chord(for: event) else {
                        settings.error = "Command combinations are reserved for application menus."; return
                    }
                    settings.assign(chord, to: action)
                    recording = nil
                }.frame(height: 30).id(action)
                Button("Cancel recording") { recording = nil }
            }
            if let error = settings.error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Restore Defaults") { settings.restoreDefaults(); recording = nil }
                Spacer()
                Button("Done") { dismiss() }
            }
        }.padding(20).frame(width: 570)
    }
}

private struct HotkeyRecorder: NSViewRepresentable {
    let receive: (NSEvent) -> Void
    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView(); view.receive = receive; return view
    }
    func updateNSView(_ nsView: RecorderView, context: Context) { nsView.receive = receive }
    final class RecorderView: NSView {
        var receive: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
        override func keyDown(with event: NSEvent) { receive?(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            receive?(event); return true
        }
    }
}
