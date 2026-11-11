import SwiftUI
import SubtitleCore

struct LayoutView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var output: OutputManager
    @State private var selectedLanguageID: UUID?
    @State private var selectedOutputID: UUID?
    @State private var pendingDeleteOutputID: UUID?
    init(store: ProjectStore, output: OutputManager, initialOutputID: UUID? = nil) {
        self.store = store; self.output = output
        _selectedOutputID = State(initialValue: initialOutputID)
        _selectedLanguageID = State(initialValue: store.project.languages.first?.id)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let id = selectedOutputID, let config = store.project.outputs.first(where: { $0.id == id }) {
                HStack {
                    Button("‹ All Outputs") { selectedOutputID = nil }
                    Spacer()
                    TextField("Output name", text: Binding(get: { outputName(config) }, set: { store.renameOutput(id, to: $0) }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    Button("Delete Output…", role: .destructive) { pendingDeleteOutputID = id }
                        .disabled(!output.activeDisplayIDs.isEmpty)
                }
                Picker("Output device", selection: Binding(get: { config.displayID }, set: { store.assignDisplay($0, to: id) })) {
                    Text("No device assigned").tag(Optional<UInt32>.none)
                    ForEach(output.displays) { display in
                        let owner = store.project.outputs.first(where: { $0.displayID == display.id })
                        Text("\(display.name)\(owner.map { "  [— \(outputName($0))]" } ?? "")").tag(Optional(display.id))
                            .disabled(store.project.outputs.contains { $0.id != id && $0.displayID == display.id })
                    }
                }
                .disabled(!output.activeDisplayIDs.isEmpty)
                OutputMappingView(store: store, output: output, outputID: id)
                Divider()
                Text("Source subtitle layout").font(.headline)
                LayoutCanvas(store: store, selectedLanguageID: $selectedLanguageID, outputID: id).frame(height: 300)
                Text("Drag to move; use the corner to resize. Arrow keys move the selected Surtitle by one canvas pixel.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading) {
                    ForEach(store.project.languages) { layer in
                        Toggle(layer.name, isOn: Binding(get: { store.layoutLanguage(layer.id, outputID: id)?.isVisible ?? false }, set: { enabled in
                            store.editLayoutLanguage(layer.id, outputID: id) { $0.isVisible = enabled }
                            selectedLanguageID = layer.id
                        }))
                    }
                }
                Picker("Surtitle", selection: $selectedLanguageID) {
                    ForEach(store.project.languages) { Text($0.name).tag(Optional($0.id)) }
                }
                if let layerID = selectedLanguageID, let layer = store.layoutLanguage(layerID, outputID: id) {
                    HStack {
                        coordinate("X", \.x, layer: layer, outputID: id, range: 0...store.canvas(for: id).width)
                        coordinate("Y", \.y, layer: layer, outputID: id, range: 0...store.canvas(for: id).height)
                        coordinate("Width", \.width, layer: layer, outputID: id, range: 1...store.canvas(for: id).width)
                        coordinate("Height", \.height, layer: layer, outputID: id, range: 1...store.canvas(for: id).height)
                    }
                    HStack {
                        rotation("Rotate X", \.x, layer: layer, outputID: id)
                        rotation("Rotate Y", \.y, layer: layer, outputID: id)
                        rotation("Rotate Z", \.z, layer: layer, outputID: id)
                    }
                    Text("Canvas pixels · top-left origin").font(.caption).foregroundStyle(.secondary)
                }
                Text("Layout edits update the live output immediately. Typography is in Text Modify.").font(.caption).foregroundStyle(.secondary)
            } else {
                GroupBox("Primary Canvas") {
                    VStack(alignment: .leading) {
                        Menu("Resolution Presets") {
                            ForEach(CanvasPreset.all) { preset in
                                Button(preset.id) { store.resizeCanvas(width: preset.width, height: preset.height) }
                            }
                        }
                        HStack {
                        canvasDimension("Width", \.width)
                        canvasDimension("Height", \.height)
                        Spacer()
                        Text("pixels · 1–32,768").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Custom dimensions supported. Resizing scales source layouts and source crops; output destinations stay fixed.").font(.caption).foregroundStyle(.secondary)
                    }.padding(4)
                }
                HStack {
                    Text("Output Layouts").font(.headline)
                    Spacer()
                    Button("+ Output") { selectedOutputID = store.addOutput() }
                        .disabled(!output.activeDisplayIDs.isEmpty)
                }
                OutputPreviews(store: store, output: output, live: false) { id in
                    store.ensureOutputLayout(id)
                    selectedOutputID = id
                    selectedLanguageID = store.project.languages.first?.id
                }
                Text("Click a preview to choose and arrange the Surtitles for that output.").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(store.project.outputs.enumerated()), id: \.element.id) { index, config in
                    HStack {
                        Text(outputName(config, fallbackIndex: index))
                        Spacer()
                        Text(config.displayID.flatMap { id in output.displays.first(where: { $0.id == id })?.name } ?? "No device assigned")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: store.sessionID) { _, _ in selectedOutputID = nil; selectedLanguageID = nil }
        .onChange(of: selectedOutputID) { _, id in store.layoutOutputID = id }
        .onChange(of: selectedLanguageID) { _, id in store.selectedSurtitleID = id }
        .onAppear { store.layoutOutputID = selectedOutputID; store.selectedSurtitleID = selectedLanguageID }
        .onDisappear { store.layoutOutputID = nil }
        .alert("Delete this output layout?", isPresented: Binding(get: { pendingDeleteOutputID != nil }, set: { if !$0 { pendingDeleteOutputID = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeleteOutputID = nil }
            Button("Delete Output", role: .destructive) {
                if let id = pendingDeleteOutputID { store.removeOutput(id) }
                pendingDeleteOutputID = nil; selectedOutputID = nil
            }
        } message: {
            Text("This removes its device assignment and Surtitle layout. You can Undo immediately afterward.")
        }
    }
    private func canvasDimension(_ title: String, _ key: WritableKeyPath<CanvasDefinition, Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption)
            NumericField(value: Binding(get: { store.project.canvas[keyPath: key] }, set: { value in
                let width = key == \.width ? value : store.project.canvas.width
                let height = key == \.height ? value : store.project.canvas.height
                store.resizeCanvas(width: width.rounded(), height: height.rounded())
            }), range: 1...32768).frame(width: 120)
        }
    }
    private func outputName(_ config: OutputConfiguration, fallbackIndex: Int? = nil) -> String {
        let trimmed = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let index = fallbackIndex ?? store.project.outputs.firstIndex(where: { $0.id == config.id }) ?? 0
        return "Output \(index + 1)"
    }
    private func coordinate(_ title: String, _ key: WritableKeyPath<PixelFrame, Double>, layer: LanguageLayer, outputID: UUID, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption)
            NumericField(value: Binding(get: { layer.frame[keyPath: key] }, set: { value in
                var frame = layer.frame; frame[keyPath: key] = value
                store.setLanguageFrame(layer.id, frame: frame, outputID: outputID)
            }), range: range)
        }
    }
    private func rotation(_ title: String, _ key: WritableKeyPath<Rotation3D, Double>, layer: LanguageLayer, outputID: UUID) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption)
            NumericField(value: Binding(get: { layer.rotation[keyPath: key] }, set: { value in
                store.editLayoutLanguage(layer.id, outputID: outputID) { $0.rotation[keyPath: key] = value }
            }), range: -360...360)
        }
    }
}
