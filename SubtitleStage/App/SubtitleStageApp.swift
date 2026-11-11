import SwiftUI

@main
struct SubtitleStageApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProjectStore()
    @StateObject private var output = OutputManager()
    @StateObject private var osc = OSCController()
    var body: some Scene {
        Window("SubtitleStage", id: "operator") { OperatorView(store: store, output: output, osc: osc)
            .background(OperatorWindowBridge(store: store, output: output, appDelegate: appDelegate)) }
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("New Project") { Task { await store.newProject(); openWindow(id: "operator") } }.disabled(store.isBusy).keyboardShortcut("n")
                    Button("Open…") { Task { await store.openProject(); openWindow(id: "operator") } }.disabled(store.isBusy).keyboardShortcut("o")
                }
                CommandGroup(replacing: .saveItem) {
                    Button("Save") { Task { await store.save() } }.disabled(store.isBusy).keyboardShortcut("s")
                    Button("Save As…") { Task { await store.save(as: true) } }.disabled(store.isBusy).keyboardShortcut("s", modifiers: [.command, .shift])
                }
                CommandGroup(after: .saveItem) {
                    Divider()
                    Button("Import Document…") { store.chooseDocument() }.disabled(!store.canUseDocumentFiles)
                    Menu("Re-import") {
                        ForEach(store.project.importSources.filter(\.hasStableKeys)) { source in
                            Button(source.name) { store.chooseDocument(source: source) }
                        }
                    }.disabled(!store.canUseDocumentFiles || !store.project.importSources.contains(where: \.hasStableKeys))
                    Divider()
                    Button(store.isExporting ? "Exporting…" : "Export Cue Sheet (.xlsx)…") {
                        Task { await store.exportSpreadsheet(template: false) }
                    }.disabled(!store.canUseDocumentFiles)
                    Button("Export Import Template (.xlsx)…") {
                        Task { await store.exportSpreadsheet(template: true) }
                    }.disabled(!store.canUseDocumentFiles)
                }
                CommandGroup(replacing: .undoRedo) {
                    Button("Undo") { store.undo(outputRunning: !output.activeDisplayIDs.isEmpty) }
                        .disabled(!store.canUndo).keyboardShortcut("z")
                    Button("Redo") { store.redo(outputRunning: !output.activeDisplayIDs.isEmpty) }
                        .disabled(!store.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
                }
            }
    }
}
