import SwiftUI
import SubtitleCore

struct OperatorView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var output: OutputManager
    @ObservedObject var osc: OSCController
    @StateObject private var syphon = SyphonOutputManager()
    @StateObject private var ndi = NDIOutputManager()
    @AppStorage("SubtitleStage.OperatorLayout") private var layout = "2 Right"
    @StateObject private var controlsWindow = ShowControlsWindow()
    @State private var importSource: String?
    @State private var renumberIDs: Set<UUID>?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Project name", text: Binding(get: { store.project.name }, set: { value in store.change { $0.name = value } }))
                    .textFieldStyle(.plain).font(.headline).frame(maxWidth: 300)
                if store.isDirty { Text("Edited").foregroundStyle(.secondary) }
                Spacer()
                Picker("Layout", selection: $layout) {
                    Text("2 Left").tag("2 Left")
                    Text("2 Right").tag("2 Right")
                }.frame(width: 160)
                Button(controlsWindow.isVisible ? "Dock Show Controls" : "Float Show Controls") {
                    if controlsWindow.isVisible { controlsWindow.close() }
                    else { controlsWindow.show(store: store, output: output) }
                }
                Text("Canvas \(Int(store.project.canvas.width)) × \(Int(store.project.canvas.height))").foregroundStyle(.secondary)
            }.padding().disabled(store.isBusy)
            HSplitView {
                if layout == "2 Left" {
                    VSplitView {
                        cuePane
                        playbackPane.frame(minHeight: 250, idealHeight: 380)
                    }.frame(minWidth: 520, idealWidth: 720)
                    editPane.frame(minWidth: 460, idealWidth: 620).disabled(store.isBusy)
                } else {
                    cuePane
                    VSplitView {
                        editPane.frame(minHeight: 240, idealHeight: 380)
                        playbackPane.frame(minHeight: 250, idealHeight: 420)
                    }.frame(minWidth: 460, idealWidth: 620).disabled(store.isBusy)
                }
            }
        }.frame(minWidth: 1000, minHeight: 700)
            .onChange(of: store.sessionID) { _ in output.stopAll(); syphon.stop(); ndi.stop() }
            .onDisappear { controlsWindow.close(); syphon.stop(); ndi.stop() }
            .sheet(isPresented: Binding(get: { importSource != nil }, set: { if !$0 { importSource = nil } })) {
                ImportPreview(store: store, source: importSource ?? "")
            }
            .sheet(isPresented: Binding(get: { renumberIDs != nil }, set: { if !$0 { renumberIDs = nil } })) {
                RenumberCuesView(store: store, ids: renumberIDs ?? [])
            }
            .sheet(item: $store.documentRequest) { DocumentImportView(store: store, request: $0) }
            .alert("SubtitleStage", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }
    private var cuePane: some View {
        VStack(spacing: 0) {
            CueTable(store: store)
            cueToolbar
        }.frame(minWidth: 520, idealWidth: 720, minHeight: 300).disabled(store.isBusy)
    }
    private var editPane: some View {
        EditWorkspaceView(store: store, output: output, osc: osc, syphon: syphon, ndi: ndi)
    }
    private var playbackPane: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Playback").font(.headline)
                Spacer()
                Button("+ Output") { store.addOutput() }
                    .disabled(!output.activeDisplayIDs.isEmpty)
                Text(store.playback.isBlackout ? "BLACKOUT" : store.playback.liveFrame.map { "LIVE · \($0.cue.displayNumber)" } ?? "NO LIVE CUE")
                    .foregroundStyle(store.playback.isBlackout ? .orange : .green)
            }
            ScrollView {
                OutputPreviews(store: store, output: output, live: true)
                    .padding(.vertical, 6)
            }.disabled(store.isBusy)
            if !controlsWindow.isVisible { ShowControlsView(store: store, output: output) }
        }.padding(14)
    }
    private var cueToolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                Button("Add Cue", action: store.addCue)
                Button("Duplicate Cue", action: store.duplicateSelectedCue).disabled(store.selectedCue == nil)
                Menu("Batch (\(store.checkedCues.count))") {
                    Button("Check All") { store.checkedCueIDs = Set(store.project.cues.map(\.id)) }
                    Button("Clear Checks") { store.checkedCueIDs = [] }
                    Divider()
                    Button("Delete Checked Cues", action: store.deleteCheckedCues).disabled(store.checkedCues.isEmpty)
                    Button("Renumber Checked Cues…") { renumberIDs = Set(store.checkedCues.map(\.id)) }
                        .disabled(store.checkedCues.isEmpty)
                }
                Button("Undo") { store.undo(outputRunning: !output.activeDisplayIDs.isEmpty) }.disabled(!store.canUndo)
                Button("Redo") { store.redo(outputRunning: !output.activeDisplayIDs.isEmpty) }.disabled(!store.canRedo)
                Button("+ Surtitle") { store.selectedSurtitleID = store.addLanguage() }
                Menu("Duplicate Surtitle") {
                    ForEach(store.project.languages) { surtitle in
                        Button(surtitle.name) {
                            store.selectedSurtitleID = surtitle.id
                            store.duplicateLanguage(surtitle.id)
                        }
                    }
                }.disabled(store.project.languages.isEmpty)
                Button("Paste As Cues…") { importSource = NSPasteboard.general.string(forType: .string) ?? "" }
            }.controlSize(.small).fixedSize().padding(8)
        }.frame(height: 42)
    }
}
