import XCTest
@testable import SubtitleCore
@testable import SubtitleStage

final class CueNumberImportTests: XCTestCase {
    private func fixture() throws -> (Project, ImportSource, UUID) {
        var project = Project()
        let english = LanguageLayer.primary(canvas: project.canvas)
        project.languages.append(english)
        let primary = project.languages[0].id
        let source = ImportSource(name: "Original", kind: "xlsx", configuration: ImportConfiguration(defaultLayerID: primary), hasStableKeys: true)
        var row = row("1", layer: primary, text: "中文一"); row.key = "external-1"
        let original = try ImportDiff.plan(project: project, source: source, rows: [row], reimport: false)
        project = try ImportDiff.applying(original, selectedKeys: [row.key], to: project, after: nil, liveCueID: nil)
        project.cues[0].name = "Production name"; project.cues[0].note = "Local note"; project.cues[0].speaker = "Local speaker"
        project.cues[0].style.fontSize = 100
        project.cues[0].transition.fadeInEnabled = true
        project.outputs = [OutputConfiguration(name: "Stage", canvasID: project.canvas.id)]
        return (project, source, english.id)
    }
    private func row(_ number: String?, layer: UUID, text: String) -> DocumentImportRow {
        var row = DocumentImportRow()
        row.content.number = number; row.content.texts[layer] = text
        return row
    }
    private func plan(_ project: Project, _ source: ImportSource, _ rows: [DocumentImportRow]) throws -> ImportPlan {
        try ImportDiff.plan(project: project, source: source, rows: rows, reimport: false, matchMode: .cueNumber)
    }
    func testDifferentSurtitleMergesIntoSameCueAndPreservesProduction() throws {
        let (project, source, english) = try fixture()
        var incoming = row("1", layer: english, text: "English one")
        incoming.content.speaker = "Should not overwrite"; incoming.content.note = "Should not overwrite"
        let diff = try plan(project, source, [incoming])
        XCTAssertEqual(diff.items[0].change, .modified)
        XCTAssertEqual(diff.items[0].cueID, project.cues[0].id)
        XCTAssertFalse(diff.items[0].conflict)
        let result = try ImportDiff.applying(diff, selectedKeys: Set(diff.items.map(\.key)), to: project, after: nil, liveCueID: nil)
        var expected = project; expected.cues[0].translations[english] = "English one"
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.cues.count, 1)
        XCTAssertEqual(result.cues[0].text, "中文一")
        XCTAssertEqual(result.cues[0].importOrigin, project.cues[0].importOrigin)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(result)), result)
    }
    func testRepeatIsUnchangedAndExistingTargetReplacementNeedsConfirmation() throws {
        var (project, source, english) = try fixture()
        project.cues[0].translations[english] = "Already imported"
        XCTAssertEqual(try plan(project, source, [row("1", layer: english, text: "Already imported")]).items[0].change, .unchanged)
        for text in ["Revised", ""] {
            let diff = try plan(project, source, [row("1", layer: english, text: text)])
            XCTAssertTrue(diff.items[0].conflict)
            XCTAssertEqual(try ImportDiff.applying(diff, selectedKeys: [], to: project, after: nil, liveCueID: nil), project)
            let result = try ImportDiff.applying(diff, selectedKeys: Set(diff.items.map(\.key)), to: project, after: nil, liveCueID: nil)
            XCTAssertEqual(result.cues[0].translations[english], text)
            XCTAssertEqual(result.cues[0].text, project.cues[0].text)
        }
    }
    func testUnknownNumbersAreNewAndAbsentCuesAreNeverDeleted() throws {
        let (project, source, english) = try fixture()
        let diff = try plan(project, source, [row("2", layer: english, text: "New")])
        XCTAssertEqual(diff.items.map(\.change), [.new])
        let result = try ImportDiff.applying(diff, selectedKeys: Set(diff.items.map(\.key)), to: project, after: project.cues[0].id, liveCueID: nil)
        XCTAssertEqual(result.cues.count, 2)
        XCTAssertEqual(result.cues[0], project.cues[0])
        XCTAssertEqual(result.cues[1].displayNumber, "2")
        XCTAssertNil(result.cues[1].importOrigin)
        XCTAssertEqual(result.importSources, project.importSources)
    }
    func testAmbiguousAndMissingNumbersRejectedWithoutGuessing() throws {
        var (project, source, english) = try fixture()
        let incoming = row("1", layer: english, text: "One")
        XCTAssertThrowsError(try plan(project, source, [incoming, row(" 1 ", layer: english, text: "Two")]))
        XCTAssertThrowsError(try plan(project, source, [row(nil, layer: english, text: "Missing")]))
        project.cues.append(Cue(displayNumber: "1", text: "Duplicate existing number"))
        XCTAssertThrowsError(try plan(project, source, [incoming]))
        var ignored = incoming; ignored.ignored = true
        XCTAssertTrue(try plan(project, source, [ignored]).items.isEmpty)
    }
    func testNumberMatchingTrimsEdgesButPreservesLeadingZeros() throws {
        let (project, source, english) = try fixture()
        let diff = try plan(project, source, [row(" 1 ", layer: english, text: "Match"), row("001", layer: english, text: "Distinct")])
        XCTAssertEqual(diff.items.map(\.change), [.modified, .new])
        XCTAssertEqual(diff.items[0].cueID, project.cues[0].id)
    }
    @MainActor func testDefaultModeLiveProtectionAndSingleUndo() throws {
        let (project, source, english) = try fixture()
        let store = ProjectStore()
        let request = DocumentImportRequest(url: URL(fileURLWithPath: "/tmp/show.xlsx"))
        XCTAssertEqual(DocumentImportSession(request: request, store: store).matchMode, .source)
        store.change { $0 = project }
        XCTAssertEqual(DocumentImportSession(request: request, store: store).matchMode, .cueNumber)
        XCTAssertEqual(DocumentImportSession(request: DocumentImportRequest(url: request.url, source: source), store: store).matchMode, .source)
        let diff = try plan(project, source, [row("1", layer: english, text: "One"), row("2", layer: english, text: "Two")])
        let keys = Set(diff.items.map(\.key))
        XCTAssertThrowsError(try ImportDiff.applying(diff, selectedKeys: keys, to: project, after: nil, liveCueID: project.cues[0].id))
        let result = try ImportDiff.applying(diff, selectedKeys: keys, to: project, after: nil, liveCueID: nil)
        try store.commitImport(result, baseline: project, sessionID: store.sessionID, affected: [project.cues[0].id])
        XCTAssertEqual(store.project.cues.count, 2)
        store.undo(); XCTAssertEqual(store.project, project)
        store.redo(); XCTAssertEqual(store.project, result)
    }
}

extension CueNumberImportTests {
    @MainActor func testNewSurtitleIsStagedAndRemovedWithoutMutatingShow() throws {
        let store = ProjectStore()
        store.addCue()
        let baseline = store.project
        let session = DocumentImportSession(request: DocumentImportRequest(url: URL(fileURLWithPath: "/tmp/show.xlsx")), store: store)
        let id = try session.addSurtitle(name: "English", column: 2)
        XCTAssertEqual(session.configuration.columns[2], .text(id))
        XCTAssertEqual(session.languages.count, baseline.languages.count + 1)
        XCTAssertEqual(store.project, baseline)
        XCTAssertThrowsError(try session.addSurtitle(name: "English", column: 3))
        XCTAssertThrowsError(try session.addSurtitle(name: "  ", column: 3))
        session.removeDraftSurtitle(id)
        XCTAssertNil(session.configuration.columns[2])
        XCTAssertEqual(session.languages, baseline.languages)
        XCTAssertEqual(store.project, baseline)
        _ = try session.addSurtitle(name: "日本語", column: 3)
        session.cancel()
        XCTAssertEqual(store.project, baseline)
    }
    @MainActor func testNewSurtitleAndNumberMergeApplyAsOneUndo() async throws {
        let (project, _, _) = try fixture()
        let store = ProjectStore()
        store.change { $0 = project }
        let session = DocumentImportSession(request: DocumentImportRequest(url: URL(fileURLWithPath: "/tmp/show.xlsx")), store: store)
        let id = try session.addSurtitle(name: "日本語", column: 3)
        session.rows = [row("1", layer: id, text: "日本語の台詞")]
        session.review()
        for _ in 0..<500 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(session.error)
        XCTAssertEqual(session.plan?.items.first?.change, .modified)
        session.apply(store: store) {}
        for _ in 0..<500 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(session.error)
        XCTAssertFalse(session.busy)
        XCTAssertEqual(store.project.cues.count, project.cues.count)
        XCTAssertEqual(store.project.cues[0].id, project.cues[0].id)
        XCTAssertEqual(store.project.cues[0].translations[id], "日本語の台詞")
        XCTAssertEqual(store.project.languages.last?.id, id)
        XCTAssertNotNil(store.project.outputs[0].languageLayouts[id])
        XCTAssertEqual(store.project.cues[0].importOrigin, project.cues[0].importOrigin)
        try store.project.validate()
        let result = store.project
        store.undo(); XCTAssertEqual(store.project, project)
        store.redo(); XCTAssertEqual(store.project, result)
    }
    @MainActor func testStalePreviewDoesNotAddDraftSurtitle() async throws {
        let (project, _, _) = try fixture()
        let store = ProjectStore(); store.change { $0 = project }
        let session = DocumentImportSession(request: DocumentImportRequest(url: URL(fileURLWithPath: "/tmp/show.xlsx")), store: store)
        let id = try session.addSurtitle(name: "New", column: 4)
        session.rows = [row("1", layer: id, text: "new")]
        session.review()
        for _ in 0..<500 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
        store.change { $0.name = "Changed during preview" }
        let changed = store.project
        session.apply(store: store) {}
        for _ in 0..<500 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(session.error)
        XCTAssertEqual(store.project, changed)
        XCTAssertFalse(store.project.languages.contains { $0.id == id })
    }
}
