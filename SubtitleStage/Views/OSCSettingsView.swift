import SwiftUI

struct OSCSettingsView: View {
    @ObservedObject var controller: OSCController
    @ObservedObject var store: ProjectStore
    @AppStorage("oscListenPort") private var port = "8000"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OSC Control").font(.title2)
            HStack {
                Text("UDP port")
                TextField("UDP port", text: $port).textFieldStyle(.roundedBorder)
                    .frame(width: 100).disabled(controller.isRunning)
            }
            HStack {
                Button(controller.isRunning ? "Stop OSC" : "Start OSC") {
                    if controller.isRunning { controller.stop() }
                    else { controller.start(port: port, store: store) }
                }
                Text(controller.status).textSelection(.enabled)
            }
            Text("Receives IPv4 UDP on this Mac, including the local network. Start manually each session.")
                .font(.caption).foregroundStyle(.secondary)
            Text("/subtitle/go\n/subtitle/previous\n/subtitle/blackout  (toggle; optional 1 or 0)\n/subtitle/cue/{UUID}")
                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Text("GO / Previous / Cue: no arguments. Blackout: integer 1 = on, 0 = restore; no argument = toggle blackout / restore. Only immediate bundles are supported.")
                .font(.caption)
            if let id = store.playback.selectedCueID {
                Text("Selected cue: /subtitle/cue/\(id.uuidString)").textSelection(.enabled)
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }
}
