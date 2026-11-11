import SwiftUI
import AppKit
import SubtitleCore

struct NDISettingsView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var ndi: NDIOutputManager
    @AppStorage(NDIRuntimeLocation.preferenceKey) private var runtimePath = ""
    private var running: Bool { ndi.isStarting || !ndi.activeOutputIDs.isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NDI® — Network Video").font(.headline)
            Text("Sends the live cue over the local network using each output's Layout and Region Mapping. Start does not GO. Allow local network access when macOS asks.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(store.project.outputs) { output in
                GroupBox(output.name.isEmpty ? "Output" : output.name) {
                    VStack(alignment: .leading) {
                        Toggle("Enable NDI", isOn: binding(output.id, \.isEnabled, output.ndi.isEnabled))
                        TextField("Source name (blank uses output name)", text: binding(output.id, \.sourceName, output.ndi.sourceName))
                        Toggle("Transparent background", isOn: binding(output.id, \.transparent, output.ndi.transparent))
                        Picker("Frame rate", selection: binding(output.id, \.framesPerSecond, output.ndi.framesPerSecond)) {
                            Text("30 fps").tag(30); Text("60 fps").tag(60)
                        }
                        let canvas = store.canvas(for: output.id)
                        let size = output.resolution ?? PixelSize(width: canvas.width, height: canvas.height)
                        Text("\(Int(size.width)) × \(Int(size.height)) pixels · " + (output.isEnabled ? "Output enabled" : "Output disabled in Layout"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.disabled(running || store.isBusy)
                }
            }
            HStack {
                Button(ndi.isStarting ? "Starting…" : "Start NDI") { ndi.start(store: store, runtimePath: runtimePath) }.disabled(running || store.isBusy)
                Button("Stop NDI") { ndi.stop() }.disabled(!running)
                if !ndi.activeOutputIDs.isEmpty { Text("Receivers: \(ndi.connectionCount)").font(.caption) }
            }
            if let status = ndi.status { Text(status).font(.caption).textSelection(.enabled) }
            Text("Blackout fades to zero alpha when transparent, or black when opaque. Stop removes the source; receivers may hold the last frame. Changing signal size/settings stops NDI for review.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("NDI Runtime") {
                VStack(alignment: .leading) {
                    Text(runtimePath.isEmpty ? (NDIRuntimeLocation.automatic.map { "Automatic: " + $0 } ?? "Not installed") : runtimePath)
                        .font(.caption).textSelection(.enabled)
                    HStack {
                        Button("Choose libndi.dylib…") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                            panel.message = "Choose libndi.dylib from the official NDI Runtime or SDK. Restart SubtitleStage to switch a runtime already loaded."
                            if panel.runModal() == .OK, let url = panel.url { runtimePath = url.path }
                        }
                        Button("Use Automatic") { runtimePath = "" }
                        Link("Install NDI Runtime", destination: URL(string: "https://ndi.link/NDIRedistV6Apple")!)
                    }.disabled(running)
                }
            }
            Text("NDI® is a registered trademark of Vizrt NDI AB.").font(.caption2).foregroundStyle(.secondary)
            Link("About NDI", destination: URL(string: "https://ndi.video/")!)
        }
    }
    private func binding<T>(_ id: UUID, _ key: WritableKeyPath<NDISettings, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { store.project.outputs.first { $0.id == id }?.ndi[keyPath: key] ?? fallback }, set: { value in
            guard !running else { return }
            store.editOutputMapping(id) { $0.ndi[keyPath: key] = value }
        })
    }
}
