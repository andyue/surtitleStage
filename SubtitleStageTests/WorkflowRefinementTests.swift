import AppKit
import Combine
import XCTest
@testable import SubtitleCore
@testable import SubtitleStage

final class WorkflowRefinementTests: XCTestCase {
    @MainActor
    func testUnchangedNDIConnectionCountsDoNotInvalidateViews() {
        let manager = NDIOutputManager()
        var changes = 0
        let subscription = manager.objectWillChange.sink { changes += 1 }
        for _ in 0..<120 { manager.updateConnectionCount(0) }
        XCTAssertEqual(changes, 0)
        manager.updateConnectionCount(1)
        for _ in 0..<120 { manager.updateConnectionCount(1) }
        XCTAssertEqual(changes, 1)
        withExtendedLifetime(subscription) {}
    }
    func testNewDefaultsAndLegacyValuesPreserved() throws {
        var project = Project()
        XCTAssertEqual(project.transitions.blackoutFadeDuration, 1)
        XCTAssertEqual(project.languages[0].frame.height, project.canvas.height * 0.2)
        project.transitions.blackoutFadeDuration = 0.3
        project.languages[0].frame = PixelFrame(x: -200, y: -100, width: 3000, height: 500)
        project.languages[0].style.lineSpacing = -40
        let loaded = try ProjectCodec.decode(ProjectCodec.encode(project))
        XCTAssertEqual(loaded, project)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: ProjectCodec.encode(Project())) as? [String: Any])
        json["projectFormatVersion"] = 11
        let migrated = try ProjectCodec.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.projectFormatVersion, 12)
    }
    @MainActor
    func testTightLineSpacingActuallyReducesTextHeightAndSelectionBox() {
        var style = TextStyle(); style.fontSize = 72; style.lineSpacing = 0
        let frame = PixelFrame(x: 0, y: 0, width: 1000, height: 1080)
        let normal = CanvasContentRenderer.selectionFrame(text: "第一行\n第二行\n第三行", style: style, frame: frame)
        style.lineSpacing = -30
        let tight = CanvasContentRenderer.selectionFrame(text: "第一行\n第二行\n第三行", style: style, frame: frame)
        XCTAssertLessThan(tight.height, normal.height - 30)
        XCTAssertEqual(tight.y + tight.height / 2, frame.y + frame.height / 2)
        XCTAssertLessThan(tight.height, frame.height / 2)
    }
    @MainActor
    func testRowHeightCacheAndLargeShowBenchmark() {
        CueRowMetrics.resetCache()
        let texts = (0..<3000).map { "字幕 \($0)\nEnglish line \($0)" }
        let start = Date()
        let original = texts.map { CueRowMetrics.height(texts: [$0], columnWidth: 220) }
        let cold = Date().timeIntervalSince(start)
        let measured = CueRowMetrics.measurementCount
        let repeatStart = Date()
        for _ in 0..<10 {
            XCTAssertEqual(texts.map { CueRowMetrics.height(texts: [$0], columnWidth: 220) }, original)
        }
        let warm = Date().timeIntervalSince(repeatStart) / 10
        XCTAssertEqual(CueRowMetrics.measurementCount, measured)
        _ = CueRowMetrics.height(texts: [texts[0]], columnWidth: 110)
        _ = CueRowMetrics.height(texts: [texts[0] + " changed"], columnWidth: 220)
        XCTAssertEqual(CueRowMetrics.measurementCount, measured + 2)
        print("ROW_HEIGHT_BENCHMARK 3000 cues cold=\(cold)s cached=\(warm)s per pass")
    }
    @MainActor
    func testRecentProjectsPersistDeduplicateAndMissingFilePreservesProject() async throws {
        let suite = "SubtitleStageTests.Recent." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ProjectStore(recentDefaults: defaults)
        let missing = URL(fileURLWithPath: "/tmp/missing-\(UUID()).substage")
        for i in 0..<12 { store.rememberRecentProject(URL(fileURLWithPath: "/tmp/recent-\(i).substage")) }
        store.rememberRecentProject(missing); store.rememberRecentProject(missing)
        XCTAssertEqual(store.recentProjectURLs.count, 10)
        XCTAssertEqual(store.recentProjectURLs.first, missing)
        XCTAssertEqual(ProjectStore(recentDefaults: defaults).recentProjectURLs, store.recentProjectURLs)
        let before = store.project
        await store.openRecentProject(missing)
        XCTAssertEqual(store.project, before)
        XCTAssertNotNil(store.errorMessage)
        store.clearRecentProjects()
        XCTAssertTrue(ProjectStore(recentDefaults: defaults).recentProjectURLs.isEmpty)
    }
    @MainActor
    func testProductionSampleSinglePage() async throws {
        guard let path = ProcessInfo.processInfo.environment["GLYPHEO_TEST_FILE"] else { throw XCTSkip("Local production sample") }
        let store = ProjectStore()
        let session = DocumentImportSession(request: DocumentImportRequest(url: URL(fileURLWithPath: path)), store: store)
        session.load()
        for _ in 0..<3000 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(session.busy); XCTAssertNil(session.error)
        XCTAssertEqual(session.rows.count, 2839)
        XCTAssertEqual(session.textColumns, [3, 4, 5, 6])
        XCTAssertEqual(session.importProject.languages.count, 4)
        XCTAssertTrue(session.rows.allSatisfy { $0.content.note == nil })
        XCTAssertNotNil(session.plan)
        XCTAssertTrue(store.project.cues.isEmpty)
    }
    @MainActor
    func testSinglePageImportPreviewsAndAppliesOnce() async throws {
        var input = Project(); input.cues = [Cue(displayNumber: "1", text: "中文\nEnglish")]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
        try SpreadsheetExporter.data(project: input).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(), before = store.project
        let session = DocumentImportSession(request: DocumentImportRequest(url: url), store: store)
        session.load()
        for _ in 0..<3000 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(session.busy)
        XCTAssertNil(session.error)
        XCTAssertEqual(store.project, before)
        XCTAssertNotNil(session.plan)
        XCTAssertEqual(session.selectedKeys.count, 1)
        XCTAssertEqual(session.configuration.columns[0], .key)
        XCTAssertEqual(session.configuration.columns[1], .number)
        XCTAssertEqual(session.configuration.columns[3], .ignore)
        XCTAssertEqual(session.importProject.languages.count, 1)
        var completed = false
        session.apply(store: store) { completed = true }
        for _ in 0..<3000 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(session.busy)
        XCTAssertNil(session.error); XCTAssertTrue(completed)
        XCTAssertEqual(store.project.cues.first?.text, input.cues[0].text)
        store.undo(); XCTAssertEqual(store.project, before)
    }
}
