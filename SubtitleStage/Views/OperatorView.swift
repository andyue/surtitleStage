import SwiftUI
import SubtitleCore

struct OperatorView: View {
    @ObservedObject var store: ProjectStore
    @ObservedObject var output: OutputManager
    @ObservedObject var osc: OSCController
    @StateObject private var syphon = SyphonOutputManager()
    @StateObject private var ndi = NDIOutputManager()
    @State private var editWorkspace = "Text Modify"
    @State private var importSource: String?
    @State private var renumberIDs: Set<UUID>?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Project name", text: Binding(get: { store.project.name }, set: { value in store.change { $0.name = value } }))
                    .textFieldStyle(.plain).font(.headline).frame(maxWidth: 300)
                if store.isDirty { Text("Edited").foregroundStyle(.secondary) }
                Spacer()
                Text("Canvas \(Int(store.project.canvas.width)) × \(Int(store.project.canvas.height))").foregroundStyle(.secondary)
            }.padding().disabled(store.isBusy)
            HSplitView {
                VSplitView {
                    VStack(spacing: 0) {
                        CueTable(store: store)
                        cueToolbar
                    }.frame(minHeight: 300, idealHeight: 520)
                    VStack(spacing: 10) {
                        HStack {
                            Text("Edit").font(.headline)
                            Spacer()
                            ViewThatFits(in: .horizontal) {
                                workspacePicker.pickerStyle(.segmented).fixedSize()
                                workspacePicker.pickerStyle(.menu)
                            }.frame(maxWidth: 560)
                            Spacer()
                            Text("Canvas \(Int(store.project.canvas.width)) × \(Int(store.project.canvas.height))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ScrollView {
                            if editWorkspace == "Layout" { LayoutView(store: store, output: output) }
                            else if editWorkspace == "Cue Details" { CueDetailsView(store: store) }
                            else if editWorkspace == "Video Output" { VideoOutputView(store: store, syphon: syphon, ndi: ndi) }
                            else if editWorkspace == "OSC" { OSCSettingsView(controller: osc, store: store) }
                            else { TextModifyView(store: store) }
                        }
                    }.padding(12).frame(minHeight: 260, idealHeight: 380)
                }.frame(minWidth: 520, idealWidth: 720).disabled(store.isBusy)
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
                    transport
                }.padding(14).frame(minWidth: 460, idealWidth: 620)
            }
        }.frame(minWidth: 1000, minHeight: 700)
            .onChange(of: store.sessionID) { _, _ in output.stopAll(); syphon.stop(); ndi.stop() }
            .onDisappear { syphon.stop(); ndi.stop() }
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
    private var workspacePicker: some View {
        Picker("Edit", selection: $editWorkspace) {
            Text("Layout Setting").tag("Layout")
            Text("Text Modify").tag("Text Modify")
            Text("Cue Details").tag("Cue Details")
            Text("OSC").tag("OSC")
            Text("Video Output").tag("Video Output")
        }.labelsHidden()
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
    private var transport: some View {
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
                Text("Space: GO · ←: Previous · B: Blackout · Esc exits output")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(4)
        }
    }
    private func durationField(_ keyPath: WritableKeyPath<TransitionSettings, Double>) -> some View {
        NumericField(value: Binding(get: { store.project.transitions[keyPath: keyPath] }, set: { value in
            store.change { $0.transitions[keyPath: keyPath] = min(10, max(0, value)) }
        }), range: 0...10, step: 0.1)
        .frame(width: 82)
    }
}
