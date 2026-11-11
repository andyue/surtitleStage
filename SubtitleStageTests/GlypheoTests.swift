import XCTest
@testable import SubtitleCore

final class GlypheoTests: XCTestCase {
    func fixture(text: String = "中文\nEnglish", duplicate: Bool = false, enabled: Bool = true) throws -> Data {
        func ref(_ i: Int) -> [String: Int] { ["CF$UID": i] }
        let objects: [Any] = ["$null",
            ["tracks": ref(2), "groups": ref(3)],
            ["NS.objects": [ref(4)]], ["NS.objects": [ref(5)]],
            ["identifier": ref(6), "name": ref(7)],
            ["name": ref(8), "surtitles": ref(9)],
            "track-id", "中文", "Act 1",
            ["NS.objects": duplicate ? [ref(10), ref(10)] : [ref(10)]],
            ["uid": 123456, "enable": enabled, "trackSurtitles": ref(11)],
            ["NS.keys": [ref(6)], "NS.objects": [ref(12)]],
            ["attributedString": ref(13)], ["NSString": ref(14)], ["NS.string": text]]
        return try PropertyListSerialization.data(fromPropertyList: ["$archiver": "NSKeyedArchiver", "$top": ["root": ref(1)], "$objects": objects], format: .binary, options: 0)
    }
    func testTracksOrderAndMultilineText() throws {
        let parsed = try GlypheoImporter.parse(data: fixture())
        XCTAssertEqual(parsed.kind, "glypheo")
        let rows = try XCTUnwrap(parsed.sheets.first).rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].cells[3], "中文")
        XCTAssertEqual(rows[1].cells[0], "123456")
        XCTAssertEqual(rows[1].cells[2], "Act 1")
        XCTAssertEqual(rows[1].cells[3], "中文\nEnglish")
    }
    func testInvalidArchivesAndDuplicateIDsRejected() throws {
        XCTAssertThrowsError(try GlypheoImporter.parse(data: Data("invalid".utf8)))
        XCTAssertThrowsError(try GlypheoImporter.parse(data: fixture(duplicate: true)))
    }
    func testDisabledCuesRemainIgnoredThroughMapping() throws {
        let parsed = try GlypheoImporter.parse(data: fixture(enabled: false))
        let project = Project()
        let layer = try XCTUnwrap(project.languages.first)
        var config = ImportConfiguration(defaultLayerID: layer.id)
        config.columns = [0: .key, 1: .number, 3: .text(layer.id)]
        let rows = try ImportMapping.rows(sheet: XCTUnwrap(parsed.sheets.first), configuration: config, languages: project.languages)
        XCTAssertTrue(try XCTUnwrap(rows.first).ignored)
        XCTAssertEqual(rows.first?.content.texts[layer.id], "中文\nEnglish")
    }
    func testReimportPreservesCueIdentity() throws {
        let project = Project(), layer = project.languages[0].id
        var config = ImportConfiguration(defaultLayerID: layer)
        config.columns = [0: .key, 1: .number, 2: .note, 3: .text(layer)]
        let source = ImportSource(name: "Test.glypheo", kind: "glypheo", configuration: config, hasStableKeys: true)
        func rows(_ text: String) throws -> [DocumentImportRow] {
            let document = try GlypheoImporter.parse(data: fixture(text: text))
            return try ImportMapping.rows(sheet: XCTUnwrap(document.sheets.first), configuration: config, languages: project.languages)
        }
        let first = try ImportDiff.plan(project: project, source: source, rows: rows("Original"), reimport: false)
        let imported = try ImportDiff.applying(first, selectedKeys: ["123456"], to: project, after: nil, liveCueID: nil)
        let update = try ImportDiff.plan(project: imported, source: source, rows: rows("Updated"), reimport: true)
        XCTAssertEqual(update.items.first?.change, .modified)
        let updated = try ImportDiff.applying(update, selectedKeys: ["123456"], to: imported, after: nil, liveCueID: nil)
        XCTAssertEqual(updated.cues.first?.id, imported.cues.first?.id)
        XCTAssertEqual(updated.cues.count, 1)
    }
    func testLocalProductionSample() throws {
        guard let path = ProcessInfo.processInfo.environment["GLYPHEO_TEST_FILE"] else { throw XCTSkip("Local production sample is not distributed with source.") }
        let parsed = try GlypheoImporter.parse(url: URL(fileURLWithPath: path))
        let sheet = try XCTUnwrap(parsed.sheets.first)
        XCTAssertEqual(sheet.rows.count, 2840)
        XCTAssertEqual(sheet.columnCount, 7)
        XCTAssertEqual(Set(sheet.rows.dropFirst().compactMap { $0.cells[0] }).count, 2839)
        XCTAssertTrue(sheet.rows.contains { $0.cells[2] == "Act 2" })
    }
}
