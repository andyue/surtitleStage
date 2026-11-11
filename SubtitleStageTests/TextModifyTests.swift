import XCTest
import AppKit
import SubtitleCore
@testable import SubtitleStage

final class TextModifyTests: XCTestCase {
    @MainActor
    func testBatchChangesOnlyOnePropertyAndSurtitle() async throws {
        let store = ProjectStore()
        store.addCue(); let a = store.selectedCue!.id
        store.addCue(); let b = store.selectedCue!.id
        let primary = store.project.languages[0].id
        let secondary = store.addLanguage()
        var style = TextStyle(); style.fontSize = 120; style.color = TextColor(red: 1, green: 0, blue: 0)
        store.modifyTextStyle(cueID: a, surtitleID: primary, property: .fontSize, style: style)
        store.modifyTextStyle(cueID: b, surtitleID: primary, property: .color, style: style)
        store.modifyTextStyle(cueID: b, surtitleID: secondary, property: .fontSize, style: style)
        store.playback.selectedCueID = a; store.go()
        style.fontSize = 144
        store.modifyTextStyle(cueID: a, surtitleID: primary, property: .fontSize, style: style, batch: true)
        let first = store.project.cues[0], second = store.project.cues[1]
        XCTAssertEqual(store.textStyle(cue: second, surtitleID: primary).fontSize, 144)
        XCTAssertEqual(store.textStyle(cue: first, surtitleID: primary).color, TextColor())
        XCTAssertEqual(store.textStyle(cue: second, surtitleID: primary).color, style.color)
        XCTAssertNil(first.styleOverrides[secondary])
        XCTAssertEqual(second.styleOverrides[secondary]?.fontSize, 120)
        XCTAssertEqual(store.playback.liveFrame?.style(for: store.project.languages[0]).fontSize, 144)
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(store.project)), store.project)
    }
    @MainActor
    func testEachBatchPropertyPreservesOtherFormatting() async throws {
        for property in TextProperty.allCases {
            let store = ProjectStore(); store.addCue(); store.addCue()
            let id = store.project.languages[0].id
            var desired = TextStyle()
            desired.fontName = "Helvetica"; desired.fontSize = 103; desired.characterSpacing = 3
            desired.lineSpacing = 15; desired.color = TextColor(red: 0.2, green: 0.4, blue: 0.7)
            desired.italic = true; desired.underline = true; desired.strikethrough = true; desired.alignment = .right
            store.modifyTextStyle(cueID: store.selectedCue!.id, surtitleID: id, property: property, style: desired, batch: true)
            var expected = TextStylePatch(); expected.copy(property, from: desired)
            for cue in store.project.cues { XCTAssertEqual(cue.styleOverrides[id], expected) }
            XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(store.project)), store.project)
        }
    }
    func testLegacyFormattingDefaultsAndOutputStylePreservation() throws {
        let data = Data("""
        {"fontName":"Helvetica","fontSize":80,"alignment":"center","characterSpacing":0,"lineSpacing":8}
        """.utf8)
        let style = try JSONDecoder().decode(TextStyle.self, from: data)
        XCTAssertEqual(style.color, TextColor()); XCTAssertFalse(style.italic); XCTAssertFalse(style.underline)
        var project = Project(); project.cues = [Cue(style: style)]
        let layerID = project.languages[0].id
        var patch = TextStylePatch(); patch.underline = true
        project.cues[0].styleOverrides[layerID] = patch
        var layer = project.languages[0]; layer.usesCueStyle = false; layer.style.fontSize = 222
        XCTAssertEqual(LiveFrame(cue: project.cues[0], project: project).style(for: layer).fontSize, 222)
        XCTAssertTrue(LiveFrame(cue: project.cues[0], project: project).style(for: layer).underline)
    }
    @MainActor
    func testRowsGrowForWrapsAndNewlines() async {
        let one = CueRowMetrics.height(texts: ["One line", "字幕"], columnWidth: 220)
        XCTAssertLessThanOrEqual(one, 36)
        XCTAssertGreaterThan(CueRowMetrics.height(texts: ["One\nTwo\nThree"], columnWidth: 220), one * 2)
        XCTAssertGreaterThan(CueRowMetrics.height(texts: [String(repeating: "中文字幕", count: 20)], columnWidth: 220), one)
        XCTAssertGreaterThan(CueRowMetrics.height(texts: ["One\n"], columnWidth: 220), one)
    }
    func testInvalidColorRejected() throws {
        var project = Project(); project.cues = [Cue()]
        var patch = TextStylePatch(); patch.color = TextColor(red: -1)
        project.cues[0].styleOverrides[project.languages[0].id] = patch
        XCTAssertThrowsError(try ProjectCodec.encode(project))
    }
}
