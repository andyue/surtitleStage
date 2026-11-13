import AppKit
import XCTest
@testable import SubtitleCore
@testable import SubtitleStage

final class SurtitleWorkflowTests: XCTestCase {
    @MainActor
    func testReorderPrimaryPreservesTextStylesLayoutLiveAndSerialization() throws {
        let store = ProjectStore()
        let a = store.project.languages[0].id, b = store.addLanguage(), c = store.addLanguage()
        store.addCue()
        let cue = try XCTUnwrap(store.selectedCue?.id)
        for (id, text) in [(a, "中文"), (b, "English"), (c, "日本語")] { store.setText(text, cueID: cue, languageID: id) }
        store.addOutput()
        store.go()
        let before = store.project
        XCTAssertTrue(store.moveSurtitle(id: c, to: a))
        XCTAssertEqual(store.project.languages.map(\.id), [c, a, b])
        for id in [a, b, c] {
            XCTAssertEqual(store.project.text(for: store.project.cues[0], languageID: id), before.text(for: before.cues[0], languageID: id))
        }
        XCTAssertEqual(store.project.outputs, before.outputs)
        XCTAssertEqual(store.project.cues[0].styleOverrides, before.cues[0].styleOverrides)
        XCTAssertEqual(store.playback.liveCueID, cue)
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(store.project)), store.project)
        store.undo(); XCTAssertEqual(store.project, before)
        store.redo(); XCTAssertEqual(store.project.languages.first?.id, c)
        store.moveSurtitle(id: c, by: 1)
        XCTAssertEqual(store.project.languages.map(\.id), [a, c, b])
        XCTAssertEqual(store.project.cues[0].text, "中文")
        XCTAssertTrue(store.moveSurtitle(id: a, to: c))
        XCTAssertEqual(store.project.languages.map(\.id), [c, a, b])
        XCTAssertEqual(store.project.cues[0].text, "日本語")
    }

    @MainActor
    func testDeletePrimaryCleansReferencesAndUndoRestoresEverything() throws {
        let store = ProjectStore()
        let a = store.project.languages[0].id, b = store.addLanguage()
        store.addCue(); let cue = try XCTUnwrap(store.selectedCue?.id)
        store.setText("刪除", cueID: cue, languageID: a)
        store.setText("Keep", cueID: cue, languageID: b)
        store.addOutput()
        store.change { project in
            var config = ImportConfiguration(defaultLayerID: a); config.columns = [0: .text(a), 1: .text(b)]
            project.importSources = [ImportSource(name: "source", kind: "xlsx", configuration: config, hasStableKeys: true)]
            var patch = TextStylePatch(); patch.bold = true
            project.cues[0].styleOverrides[a] = patch
        }
        let before = store.project
        store.deleteSurtitle(id: a)
        XCTAssertEqual(store.project.cues[0].text, "Keep")
        XCTAssertNil(store.project.cues[0].translations[a])
        XCTAssertNil(store.project.cues[0].styleOverrides[a])
        XCTAssertTrue(store.project.outputs.allSatisfy { $0.languageLayouts[a] == nil })
        XCTAssertEqual(store.project.importSources[0].configuration.defaultLayerID, b)
        XCTAssertEqual(store.project.importSources[0].configuration.columns[0], .ignore)
        try store.project.validate()
        let remaining = store.project
        store.deleteSurtitle(id: b); XCTAssertEqual(store.project, remaining)
        store.undo(); XCTAssertEqual(store.project, before)
        XCTAssertEqual(store.selectedSurtitleID, a)
    }

    @MainActor
    func testImportAppendAndExplicitInsertionIgnoreCurrentSelection() async throws {
        var input = Project(); input.cues = [Cue(displayNumber: "new", text: "Imported")]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
        try SpreadsheetExporter.data(project: input).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        for insertAfterFirst in [false, true] {
            let store = ProjectStore(); store.addCue(); store.addCue()
            let ids = store.project.cues.map(\.id)
            store.playback.selectedCueID = ids[0]
            let session = DocumentImportSession(request: DocumentImportRequest(url: url), store: store)
            session.load()
            for _ in 0..<3000 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNil(session.error); XCTAssertNotNil(session.plan)
            XCTAssertNil(session.insertionAfterCueID)
            XCTAssertEqual(session.draftLanguages.count, 1)
            if insertAfterFirst { session.insertionAfterCueID = ids[0] }
            var completed = false
            session.apply(store: store) { completed = true }
            for _ in 0..<3000 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNil(session.error); XCTAssertTrue(completed)
            XCTAssertEqual(store.project.cues.map(\.displayNumber), insertAfterFirst ? ["1", "new", "2"] : ["1", "2", "new"])
            XCTAssertEqual(store.project.cues.filter { ids.contains($0.id) }.map(\.id), ids)
        }
    }

    @MainActor
    func testOperatorWindowDisablesFullscreenAndKeepsZoom() throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Native window check") }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        let coordinator = OperatorWindowBridge.Coordinator(store: ProjectStore(), output: OutputManager(), appDelegate: AppDelegate())
        coordinator.attach(window)
        defer { coordinator.detach(); window.delegate = nil; window.close() }
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.action, #selector(NSWindow.zoom(_:)))
    }
}
