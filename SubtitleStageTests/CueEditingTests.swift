import XCTest
import SubtitleCore
@testable import SubtitleStage

final class CueEditingTests: XCTestCase {
    @MainActor
    func testDuplicatePreservesContentAndHistoryWithoutTakingLive() async throws {
        let store = ProjectStore()
        store.addCue()
        let secondLanguage = store.addLanguage()
        var source = store.selectedCue!
        source.name = "場一"; source.note = "備註"; source.text = "繁體字幕"
        source.translations[secondLanguage] = "English"
        var patch = TextStylePatch(); patch.fontSize = 123
        source.styleOverrides[secondLanguage] = patch
        source.transition = CueTransition(fadeInEnabled: true, fadeInDuration: 2)
        store.editCue(source)
        store.go(); store.blackout()
        store.duplicateSelectedCue()
        let copy = store.selectedCue!
        XCTAssertNotEqual(copy.id, source.id)
        var expected = source; expected.id = copy.id
        XCTAssertEqual(copy, expected)
        XCTAssertEqual(store.project.cues.map(\.id), [source.id, copy.id])
        XCTAssertEqual(store.playback.liveCueID, source.id)
        XCTAssertTrue(store.playback.isBlackout)
        XCTAssertTrue(store.isDirty)
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(store.project)), store.project)
        store.undo()
        XCTAssertEqual(store.project.cues, [source])
        store.redo()
        XCTAssertEqual(store.project.cues, [source, copy])
        XCTAssertEqual(store.selectedCue?.id, copy.id)
    }

    @MainActor
    func testBatchDeleteIsAtomicAndUndoRestoresChecksAndOrder() async {
        let store = ProjectStore()
        for _ in 0..<4 { store.addCue() }
        let original = store.project.cues
        store.playback.selectedCueID = original[1].id; store.go()
        store.checkedCueIDs = [original[0].id, original[1].id]
        store.deleteCheckedCues()
        XCTAssertEqual(store.project.cues, original)
        XCTAssertNotNil(store.errorMessage)
        store.checkedCueIDs = [original[0].id, original[2].id]
        store.playback.selectedCueID = original[2].id
        store.deleteCheckedCues()
        XCTAssertEqual(store.project.cues, [original[1], original[3]])
        XCTAssertEqual(store.playback.liveCueID, original[1].id)
        XCTAssertEqual(store.selectedCue?.id, original[3].id)
        XCTAssertTrue(store.checkedCueIDs.isEmpty)
        store.undo()
        XCTAssertEqual(store.project.cues, original)
        XCTAssertEqual(store.checkedCueIDs, [original[0].id, original[2].id])
        store.redo()
        XCTAssertEqual(store.project.cues, [original[1], original[3]])
    }

    @MainActor
    func testRenumberPreviewUsesOrderAndPreservesIdentityAndPlayback() async throws {
        let store = ProjectStore()
        for _ in 0..<4 { store.addCue() }
        let original = store.project.cues
        store.go(); store.blackout()
        let live = store.playback.liveCueID
        let selected = store.playback.selectedCueID
        let ids: Set<UUID> = [original[3].id, original[1].id]
        let preview = try XCTUnwrap(store.numberPreview(ids: ids, start: 10))
        XCTAssertEqual(preview.map(\.id), [original[1].id, original[3].id])
        XCTAssertEqual(preview.map(\.newNumber), ["10", "11"])
        XCTAssertEqual(store.project.cues, original)
        XCTAssertNil(store.numberPreview(ids: ids, start: Int.max))
        XCTAssertNil(store.numberPreview(ids: ids, start: -1))
        XCTAssertNil(store.numberPreview(ids: [UUID()], start: 1))
        store.renumberCues(ids: ids, start: 10)
        XCTAssertEqual(store.project.cues.map(\.displayNumber), ["1", "10", "3", "11"])
        XCTAssertEqual(store.project.cues.map(\.id), original.map(\.id))
        XCTAssertEqual(store.playback.liveCueID, live)
        XCTAssertEqual(store.playback.selectedCueID, selected)
        XCTAssertTrue(store.playback.isBlackout)
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(store.project)), store.project)
        store.undo(); XCTAssertEqual(store.project.cues, original)
        store.redo(); XCTAssertEqual(store.project.cues[3].displayNumber, "11")
    }

    @MainActor
    func testDetailsGroupTypingAndPreserveCueContent() async throws {
        let store = ProjectStore(); store.addCue()
        let original = store.selectedCue!
        store.editCueDetail(original.id, key: \.name, value: "場")
        store.editCueDetail(original.id, key: \.name, value: "場一")
        store.endHistoryGroup()
        store.editCueDetail(original.id, key: \.note, value: "繁體／简体 notes")
        XCTAssertEqual(store.selectedCue?.name, "場一")
        XCTAssertNil(store.playback.liveCueID)
        XCTAssertEqual(try ProjectCodec.decode(ProjectCodec.encode(store.project)), store.project)
        store.undo(); XCTAssertEqual(store.selectedCue?.note, "")
        store.undo(); XCTAssertEqual(store.selectedCue, original)
    }
}
