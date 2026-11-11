import SwiftUI
import SubtitleCore

struct VideoOutputView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var syphon: SyphonOutputManager
    @ObservedObject var ndi: NDIOutputManager
    private var running: Bool { syphon.isStarting || !syphon.activeOutputIDs.isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Syphon — Inter-Application Video").font(.headline)
            Text("Publishes the live cue to local Syphon clients without an external display. Uses each output's Layout and Region Mapping. Start does not GO; use the playback controls to take a cue live.")
                .font(.caption).foregroundStyle(.secondary)
            if store.project.outputs.isEmpty { Text("Add an Output slot first. No display assignment is required.") }
            ForEach(store.project.outputs) { output in
                GroupBox(output.name.isEmpty ? "Output" : output.name) {
                    VStack(alignment: .leading) {
                        Toggle("Enable Syphon", isOn: binding(output.id, \.isEnabled, output.syphon.isEnabled))
                        TextField("Server name (blank uses output name)", text: binding(output.id, \.serverName, output.syphon.serverName))
                        Toggle("Transparent background (premultiplied alpha)", isOn: binding(output.id, \.transparent, output.syphon.transparent))
                        Picker("Frame rate", selection: binding(output.id, \.framesPerSecond, output.syphon.framesPerSecond)) {
                            Text("30 fps").tag(30)
                            Text("60 fps").tag(60)
                        }
                        let canvas = store.canvas(for: output.id)
                        let size = output.resolution ?? PixelSize(width: canvas.width, height: canvas.height)
                        Text("\(Int(size.width)) × \(Int(size.height)) pixels · " + (output.isEnabled ? "Output enabled" : "Output disabled in Layout"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.disabled(running || store.isBusy)
                }
            }
            HStack {
                Button(syphon.isStarting ? "Starting…" : "Start Syphon") { syphon.start(store: store) }.disabled(running || store.isBusy)
                Button("Stop Syphon") { syphon.stop() }.disabled(!running)
            }
            if let status = syphon.status { Text(status).font(.caption).textSelection(.enabled) }
            Text("Transparent Blackout sends zero alpha; opaque mode sends black. Receivers should use premultiplied alpha. Resolution follows Output signal resolution, or its Canvas when automatic. Changing size/settings stops Syphon; restart after review.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            NDISettingsView(store: store, ndi: ndi)
        }.padding(4)
    }
    private func binding<T>(_ id: UUID, _ key: WritableKeyPath<SyphonSettings, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { store.project.outputs.first { $0.id == id }?.syphon[keyPath: key] ?? fallback }, set: { value in
            guard !running else { return }
            store.editOutputMapping(id) { $0.syphon[keyPath: key] = value }
        })
    }
}
