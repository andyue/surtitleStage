import SwiftUI
import SubtitleCore

struct OutputMappingView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var output: OutputManager
    let outputID: UUID
    @State private var selectedRegionID: UUID?
    @State private var sourceMode = false
    @State private var pendingDelete = false
    @State private var signalWidth = ""
    @State private var signalHeight = ""
    private var running: Bool { !output.activeDisplayIDs.isEmpty }
    private var config: OutputConfiguration? { store.project.outputs.first { $0.id == outputID } }

    var body: some View {
        if let config {
            let canvas = store.canvas(for: outputID)
            let size = config.resolution ?? PixelSize(width: canvas.width, height: canvas.height)
            GroupBox("Output Mapping") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enabled", isOn: Binding(get: { config.isEnabled }, set: { value in
                        store.editOutputMapping(outputID) { $0.isEnabled = value }
                    })).disabled(running)
                    Picker("Assigned canvas", selection: Binding(get: { config.canvasID }, set: { value in
                        store.editOutputMapping(outputID) { $0.canvasID = value }
                    })) {
                        ForEach(Array(store.project.canvases.enumerated()), id: \.element.id) { index, canvas in
                            Text("Canvas \(index + 1) · \(Int(canvas.width)) × \(Int(canvas.height))").tag(canvas.id)
                        }
                    }.disabled(running)
                    HStack {
                        Toggle("Explicit signal resolution", isOn: Binding(get: { config.resolution != nil }, set: { enabled in
                            store.setOutputResolution(outputID, size: enabled ? size : nil)
                        })).disabled(running || !config.regions.isEmpty)
                        Button("Use Display Pixels") {
                            if let display = output.displays.first(where: { $0.id == config.displayID }) {
                                store.setOutputResolution(outputID, size: display.pixels)
                            }
                        }.disabled(running || !output.displays.contains(where: { $0.id == config.displayID }))
                    }
                    if config.resolution != nil {
                        HStack {
                            TextField("Signal width", text: $signalWidth).textFieldStyle(.roundedBorder)
                            Text("×")
                            TextField("Signal height", text: $signalHeight).textFieldStyle(.roundedBorder)
                            Button("Apply Size") {
                                guard let width = Double(signalWidth), let height = Double(signalHeight) else {
                                    store.errorMessage = "Enter whole pixel dimensions."; return
                                }
                                store.setOutputResolution(outputID, size: PixelSize(width: width, height: height))
                            }
                        }.disabled(running)
                    } else {
                        Text("Automatic: uses display backing pixels at output start. Offline preview uses canvas size.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if config.regions.isEmpty {
                        Picker("Full canvas mapping", selection: Binding(get: { config.scaleMode }, set: { mode in
                            store.editOutputMapping(outputID) { $0.scaleMode = mode }
                        })) { ForEach(ScaleMode.allCases, id: \.self) { Text($0.label).tag($0) } }.disabled(running)
                    }
                    HStack {
                        Text("Regions").font(.headline)
                        Spacer()
                        Button("+ Region") { selectedRegionID = store.addRegion(to: outputID, displaySize: output.displays.first { $0.id == config.displayID }?.pixels) }.disabled(running)
                        Button("Delete Region…") { pendingDelete = true }.disabled(selectedRegionID == nil || running)
                    }
                    Text("No regions = full canvas. With regions, only enabled regions render, in list order (later regions overlay earlier text).")
                        .font(.caption).foregroundStyle(.secondary)
                    if !config.regions.isEmpty {
                        Picker("Region", selection: $selectedRegionID) {
                            Text("Select region").tag(Optional<UUID>.none)
                            ForEach(config.regions) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Picker("Edit boundary", selection: $sourceMode) {
                            Text("Destination signal").tag(false)
                            Text("Source crop").tag(true)
                        }.pickerStyle(.segmented)
                        RegionMapCanvas(store: store, outputID: outputID, selectedID: $selectedRegionID, sourceMode: sourceMode)
                            .frame(height: 240)
                        if let region = config.regions.first(where: { $0.id == selectedRegionID }) {
                            TextField("Region name", text: Binding(get: { region.name }, set: { value in
                                store.editRegion(region.id, outputID: outputID, historyGroup: "region-name-\(region.id)") { $0.name = value }
                            })).textFieldStyle(.roundedBorder)
                            Toggle("Region enabled", isOn: Binding(get: { region.isEnabled }, set: { value in
                                store.editRegion(region.id, outputID: outputID) { $0.isEnabled = value }
                            })).disabled(running)
                            Picker("Scale", selection: Binding(get: { region.scaleMode }, set: { mode in
                                store.editRegion(region.id, outputID: outputID) { $0.scaleMode = mode }
                            })) { ForEach(ScaleMode.allCases, id: \.self) { Text($0.label).tag($0) } }.disabled(running)
                            Picker("Source canvas", selection: Binding(get: { region.sourceCanvasID }, set: { id in
                                guard let canvas = store.project.canvases.first(where: { $0.id == id }) else { return }
                                store.editRegion(region.id, outputID: outputID) {
                                    $0.sourceCanvasID = id
                                    $0.source = PixelFrame(x: 0, y: 0, width: canvas.width, height: canvas.height)
                                }
                            })) {
                                ForEach(Array(store.project.canvases.enumerated()), id: \.element.id) { index, canvas in
                                    Text("Canvas \(index + 1) · \(Int(canvas.width)) × \(Int(canvas.height))").tag(canvas.id)
                                }
                            }.disabled(running)
                            let source = store.project.canvases.first { $0.id == region.sourceCanvasID } ?? canvas
                            Text("Source crop · canvas pixels").font(.caption)
                            fields(region: region, source: true, size: PixelSize(width: source.width, height: source.height))
                            Text("Destination · output-signal pixels").font(.caption)
                            fields(region: region, source: false, size: size)
                        }
                    }
                    Text("Drag a region to move; drag its bottom-right handle to resize. Coordinates are whole pixels. 1:1 anchors at top-left and clips; Fit/Fill are centered. Stop Output to change signal or scale mode.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(4)
            }
            .alert("Delete region?", isPresented: $pendingDelete) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let id = selectedRegionID { store.removeRegion(id, outputID: outputID) }
                    selectedRegionID = nil
                }
            } message: { Text("Deleting the last region restores full-canvas mapping. You can Undo this change.") }
            .onAppear { signalWidth = String(Int(size.width)); signalHeight = String(Int(size.height)); selectedRegionID = config.regions.first?.id }
            .onChange(of: config.regions.map(\.id)) { _, ids in
                if !ids.contains(where: { $0 == selectedRegionID }) { selectedRegionID = ids.first }
            }
            .onChange(of: config.resolution) { _, _ in signalWidth = String(Int(size.width)); signalHeight = String(Int(size.height)) }
            .onChange(of: outputID) { _, _ in selectedRegionID = nil; signalWidth = String(Int(size.width)); signalHeight = String(Int(size.height)) }
            .onDisappear { store.endHistoryGroup() }
        }
    }
    private func fields(region: OutputRegion, source: Bool, size: PixelSize) -> some View {
        RegionFrameFields(frame: source ? region.source : region.destination) { frame in
            store.editRegion(region.id, outputID: outputID) {
                if source { $0.source = frame } else { $0.destination = frame }
            }
        }.id("\(region.id)-\(source)")
    }

}

private struct RegionMapCanvas: View {
    @ObservedObject var store: ProjectStore
    let outputID: UUID
    @Binding var selectedID: UUID?
    let sourceMode: Bool
    var body: some View {
        GeometryReader { geometry in
            if let config = store.project.outputs.first(where: { $0.id == outputID }) {
                let assigned = store.canvas(for: outputID)
                let sourceID = config.regions.first { $0.id == selectedID }?.sourceCanvasID
                let canvas = sourceMode ? (store.project.canvases.first { $0.id == sourceID } ?? assigned) : assigned
                let size = sourceMode ? PixelSize(width: canvas.width, height: canvas.height) : config.resolution ?? PixelSize(width: canvas.width, height: canvas.height)
                if let transform = CanvasTransform(canvas: size.canvas, viewportWidth: geometry.size.width, viewportHeight: geometry.size.height) {
                    ZStack(alignment: .topLeading) {
                        CanvasView(frame: LiveFrame(cue: store.selectedCue ?? Cue(), project: store.project), canvas: canvas,
                                   blackout: false, outputID: outputID, applyMapping: !sourceMode)
                        Rectangle().stroke(.gray).frame(width: size.width * transform.scale, height: size.height * transform.scale)
                            .offset(x: transform.offsetX, y: transform.offsetY).allowsHitTesting(false)
                        ForEach(config.regions.filter { !sourceMode || $0.sourceCanvasID == canvas.id }) { region in
                            RegionBox(region: region, sourceMode: sourceMode, size: size, transform: transform,
                                      selected: region.id == selectedID, select: {
                                selectedID = region.id
                                store.selectedSurtitleID = nil
                                NSApp.keyWindow?.makeFirstResponder(nil)
                            }, update: { frame in
                                store.editRegion(region.id, outputID: outputID, historyGroup: "region-drag-\(region.id)-\(sourceMode)") {
                                    if sourceMode { $0.source = frame } else { $0.destination = frame }
                                }
                            }, end: { store.endHistoryGroup() })
                        }
                    }
                }
            }
        }
    }
}

private struct RegionBox: View {
    let region: OutputRegion
    let sourceMode: Bool
    let size: PixelSize
    let transform: CanvasTransform
    let selected: Bool
    let select: () -> Void
    let update: (PixelFrame) -> Void
    let end: () -> Void
    @State private var origin: PixelFrame?
    private var frame: PixelFrame { sourceMode ? region.source : region.destination }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(selected ? Color.accentColor.opacity(0.12) : .clear)
            Rectangle().stroke(selected ? Color.accentColor : .orange, lineWidth: selected ? 2 : 1)
            Text(region.name).font(.caption).padding(2).background(.black.opacity(0.7)).foregroundStyle(.white)
            if selected {
                Rectangle().fill(Color.accentColor).frame(width: 14, height: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .highPriorityGesture(drag(resize: true))
            }
        }.frame(width: frame.width * transform.scale, height: frame.height * transform.scale)
            .contentShape(Rectangle()).onTapGesture(perform: select).gesture(drag(resize: false))
            .offset(x: transform.offsetX + frame.x * transform.scale, y: transform.offsetY + frame.y * transform.scale)
    }
    private func drag(resize: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global).onChanged { value in
            select()
            if origin == nil { origin = frame }
            guard let origin else { return }
            update(origin.adjusted(dx: value.translation.width / transform.scale, dy: value.translation.height / transform.scale,
                                   resizing: resize, canvas: size.canvas).bounded(to: size))
        }.onEnded { _ in origin = nil; end() }
    }
}

/// Stage all four values so an intermediate keystroke cannot corrupt a live region.
private struct RegionFrameFields: View {
    let frame: PixelFrame
    let apply: (PixelFrame) -> Void
    @State private var x = ""
    @State private var y = ""
    @State private var width = ""
    @State private var height = ""
    private var candidate: PixelFrame? {
        guard let x = Double(x), let y = Double(y), let width = Double(width), let height = Double(height),
              [x,y,width,height].allSatisfy({ $0.isFinite && $0.rounded() == $0 }) else { return nil }
        return PixelFrame(x: x, y: y, width: width, height: height)
    }
    var body: some View {
        HStack {
            field("X", value: $x); field("Y", value: $y)
            field("Width", value: $width); field("Height", value: $height)
            Button("Apply") { if let candidate { apply(candidate) } }.disabled(candidate == nil)
        }.onAppear(perform: reset).onChange(of: frame) { _, _ in reset() }
    }
    private func field(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption)
            TextField(title, text: value).textFieldStyle(.roundedBorder)
        }
    }
    private func reset() {
        x = String(Int(frame.x)); y = String(Int(frame.y))
        width = String(Int(frame.width)); height = String(Int(frame.height))
    }
}
