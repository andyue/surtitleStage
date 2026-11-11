import XCTest
@testable import SubtitleCore
@testable import SubtitleStage

final class SpreadsheetExportTests: XCTestCase {
    private func parse(_ data: Data, layer: UUID) throws -> ParsedDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try OfficeDocumentImporter.parse(url: url, defaultLayerID: layer)
    }
    func testExportImportsChineseMetadataAndLiteralFormulaWithoutChangingProject() throws {
        var project = Project()
        var second = LanguageLayer.primary(canvas: project.canvas)
        second.name = "English"; project.languages.append(second)
        let first = project.languages[0].id
        var cue = Cue(displayNumber: "001", note: " notes & <text>\r\nnext ", text: "繁體\n简体 😀")
        cue.speaker = "角色"
        cue.translations[second.id] = "=SUM(1,2)"
        project.cues = [cue]
        let original = project
        let parsed = try parse(SpreadsheetExporter.data(project: project), layer: first)
        XCTAssertEqual(project, original)
        XCTAssertEqual(parsed.sheets.map(\.name), ["Cue Sheet", "Import Guide"])
        let sheet = try XCTUnwrap(parsed.sheets.first)
        XCTAssertEqual(sheet.rows[1].cells[0], cue.id.uuidString)
        XCTAssertEqual(sheet.rows[1].cells[1], "001")
        XCTAssertEqual(sheet.rows[1].cells[3], cue.note)
        XCTAssertEqual(sheet.rows[1].cells[5], "=SUM(1,2)")
        var config = ImportConfiguration(defaultLayerID: first)
        config.columns = [0: .key, 1: .number, 2: .speaker, 3: .note, 4: .text(first), 5: .text(second.id)]
        let rows = try ImportMapping.rows(sheet: sheet, configuration: config, languages: project.languages)
        XCTAssertEqual(rows[0].content.texts[first], cue.text)
        XCTAssertEqual(rows[0].content.texts[second.id], cue.translations[second.id])
        XCTAssertEqual(rows[0].content.speaker, cue.speaker)
        XCTAssertEqual(rows[0].content.note, cue.note)
        XCTAssertEqual(rows[0].key, cue.id.uuidString)
    }
    func testTemplateContainsExampleAndMappingGuideEvenForEmptyProject() throws {
        let project = Project()
        let parsed = try parse(SpreadsheetExporter.data(project: project, template: true), layer: project.languages[0].id)
        XCTAssertEqual(parsed.sheets[0].rows.count, 2)
        XCTAssertEqual(parsed.sheets[0].rows[1].cells[0], "example-001")
        XCTAssertTrue(parsed.sheets[1].rows.contains { $0.cells[0] == "Source ID" })
        let empty = try parse(SpreadsheetExporter.data(project: project), layer: project.languages[0].id)
        XCTAssertEqual(empty.sheets[0].rows.count, 1)
    }
    func testUnrepresentableCellsFailInsteadOfTruncating() throws {
        var project = Project()
        project.cues = [Cue(text: String(repeating: "字", count: 32768))]
        XCTAssertThrowsError(try SpreadsheetExporter.data(project: project))
        project.cues[0].text = "bad\u{01}"
        XCTAssertThrowsError(try SpreadsheetExporter.data(project: project))
    }
    @MainActor func testFileActionsDoNotChangePlaybackAndGateDuplicateSheets() {
        let store = ProjectStore()
        store.addCue(); store.go()
        let project = store.project, live = store.playback.liveCueID
        XCTAssertTrue(store.canUseDocumentFiles)
        store.documentRequest = DocumentImportRequest(url: URL(fileURLWithPath: "/tmp/script.xlsx"))
        XCTAssertFalse(store.canUseDocumentFiles)
        store.documentRequest = nil
        store.isExporting = true
        XCTAssertFalse(store.canUseDocumentFiles)
        XCTAssertEqual(store.project, project)
        XCTAssertEqual(store.playback.liveCueID, live)
    }
}
