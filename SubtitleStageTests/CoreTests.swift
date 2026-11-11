import XCTest
@testable import SubtitleCore

final class CoreTests: XCTestCase {
    func project() -> Project {
        var p = Project()
        p.cues = [Cue(displayNumber: "1", text: "繁體中文"), Cue(displayNumber: "2", text: "简体中文"), Cue(displayNumber: "3", text: "English 日本語 한국어 🎭")]
        return p
    }
    func testNavigationSelectionAndBoundaries() {
        let p = project()
        var s = PlaybackState()
        s.selectedCueID = p.cues[1].id
        XCTAssertNil(s.liveCueID)
        s.go(in: p)
        XCTAssertEqual(s.liveCueID, p.cues[1].id)
        s.selectedCueID = p.cues[0].id
        s.go(in: p)
        XCTAssertEqual(s.liveCueID, p.cues[2].id)
        s.go(in: p)
        XCTAssertEqual(s.liveCueID, p.cues[2].id)
        s.previous(in: p); s.previous(in: p); s.previous(in: p)
        XCTAssertEqual(s.liveCueID, p.cues[0].id)
    }
    func testBlackoutAndSnapshot() {
        var p = project(); var s = PlaybackState()
        s.go(in: p)
        let original = s.liveFrame
        p.cues[0].text = "Edited"
        XCTAssertEqual(s.liveFrame, original)
        s.blackout(); s.blackout()
        XCTAssertTrue(s.isBlackout)
        s.toggleBlackout()
        XCTAssertEqual(s.liveFrame, original)
        XCTAssertFalse(s.isBlackout)
        s.setMasterOpacity(0.65)
        s.blackout(); s.go(in: p)
        XCTAssertTrue(s.isBlackout)
        XCTAssertEqual(s.visibleOpacity, 0)
        XCTAssertEqual(s.liveCueID, p.cues[1].id)
        s.toggleBlackout()
        XCTAssertEqual(s.visibleOpacity, 0.65, accuracy: 0.001)
    }
    func testEmptyPlayback() {
        var s = PlaybackState()
        s.go(in: Project()); s.previous(in: Project())
        XCTAssertNil(s.liveCueID)
    }
    func testSelectedTakeLiveRefreshAndFades() {
        var p = project()
        var state = PlaybackState()
        state.selectedCueID = p.cues[1].id
        state.showSelected(in: p)
        XCTAssertEqual(state.liveCueID, p.cues[1].id)
        p.cues[1].text = "Live correction"
        state.refreshLive(in: p)
        XCTAssertEqual(state.liveFrame?.cue.text, "Live correction")
        state.fadeOut(duration: 0.8)
        XCTAssertEqual(state.visibleOpacity, 0)
        XCTAssertEqual(state.transitionDuration, 0.8)
        state.fadeIn(duration: 0.4)
        XCTAssertEqual(state.visibleOpacity, 1)
        state.toggleBlackout(duration: 1.2)
        XCTAssertTrue(state.isBlackout)
        XCTAssertEqual(state.visibleOpacity, 0)
        XCTAssertEqual(state.transitionDuration, 1.2)
    }
    func testReorderPreservesIdentityAndFields() {
        var p = project(); let first = p.cues[0]
        p.moveCue(id: first.id, by: 2)
        XCTAssertEqual(p.cues[2], first)
        p.moveCue(id: first.id, by: 1)
        XCTAssertEqual(p.cues[2], first)
        var s = PlaybackState(); s.go(in: p); s.go(in: p)
        XCTAssertEqual(s.liveCueID, p.cues[1].id)
    }
    func testClipboard() {
        XCTAssertEqual(ClipboardImporter.parse("繁體\r\n简体\rEnglish\n \n🎭", mode: .line).map(\.text), ["繁體", "简体", "English", "🎭"])
        XCTAssertEqual(ClipboardImporter.parse("第一行\n第二行\n \nThird\nFourth\n\n", mode: .paragraph).map(\.text), ["第一行\n第二行", "Third\nFourth"])
        XCTAssertTrue(ClipboardImporter.parse(" \n\r\n", mode: .paragraph).isEmpty)
    }
    func testSerializationAndAtomicSave() throws {
        var p = project()
        p.canvases[0] = CanvasDefinition(width: 2688, height: 768)
        p.cues[0].note = "演出筆記"; p.cues[0].style.characterSpacing = 4
        p.outputs = [OutputConfiguration(displayID: 123, canvasID: p.canvas.id)]
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(p)), p)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.substage")
        try ProjectCodec.save(p, to: url)
        XCTAssertEqual(try ProjectCodec.load(from: url), p)
        p.cues.reverse()
        try ProjectCodec.save(p, to: url)
        XCTAssertEqual(try ProjectCodec.load(from: url), p)
    }
    func testInvalidProjectsRejected() throws {
        var p = project(); p.cues.append(p.cues[0])
        XCTAssertThrowsError(try ProjectCodec.encode(p))
        p = project(); p.projectFormatVersion = 99
        XCTAssertThrowsError(try ProjectCodec.decode(JSONEncoder().encode(p)))
        p = project(); p.canvases = []
        XCTAssertThrowsError(try ProjectCodec.encode(p))
        p = project(); p.canvases[0].width = 0
        XCTAssertThrowsError(try ProjectCodec.encode(p))
        XCTAssertThrowsError(try ProjectCodec.decode(Data("bad".utf8)))
    }
    func testArbitraryCanvasCoordinates() throws {
        for size in [(5760.0, 1080.0), (2688, 768), (960, 2560), (4096, 2160)] {
            let canvas = CanvasDefinition(width: size.0, height: size.1)
            let t = try XCTUnwrap(CanvasTransform(canvas: canvas, viewportWidth: 800, viewportHeight: 500))
            let preview = t.toPreview(x: 345, y: 210)
            let original = t.toCanvas(x: preview.x, y: preview.y)
            XCTAssertEqual(original.x, 345, accuracy: 0.00001)
            XCTAssertEqual(original.y, 210, accuracy: 0.00001)
            XCTAssertLessThanOrEqual(canvas.width * t.scale, 800)
            XCTAssertLessThanOrEqual(canvas.height * t.scale, 500)
        }
        XCTAssertNil(CanvasTransform(canvas: CanvasDefinition(), viewportWidth: 0, viewportHeight: 50))
    }
}
