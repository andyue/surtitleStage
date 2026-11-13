import XCTest
import SwiftUI
import AppKit
@testable import SubtitleCore
@testable import SubtitleStage

final class DocumentImportTests: XCTestCase {
    private func archive(_ files: [String: String], extension ext: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let output = root.appendingPathComponent("fixture." + ext)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", output.path] + files.keys.sorted()
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return output
    }
    private func workbook(_ cells: String) throws -> URL {
        try archive([
            "xl/workbook.xml": "<workbook xmlns:r='urn:r'><sheets><sheet name='台詞' r:id='r1'/></sheets></workbook>",
            "xl/_rels/workbook.xml.rels": "<Relationships><Relationship Id='r1' Target='worksheets/custom.xml' Type='urn:office/worksheet'/></Relationships>",
            "xl/sharedStrings.xml": "<sst><si><t>識別碼</t></si><si><r><t>繁體</t></r><r><t>台詞</t></r></si></sst>",
            "xl/worksheets/custom.xml": "<worksheet><sheetData>\(cells)</sheetData></worksheet>"
        ], extension: "xlsx")
    }
    func testSpreadsheetParsingAndExplicitMapping() throws {
        let url = try workbook("""
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><t>自訂中文欄</t></is></c></row>
        <row r="5"><c r="A5" t="inlineStr"><is><t>stable-一</t></is></c><c r="C5" t="s"><v>1</v></c></row>
        <row r="9"><c r="A9" t="inlineStr"><is><t>stable-二</t></is></c><c r="C9" t="str"><f>CONCAT()</f><v>简体中文</v></c></row>
        """)
        let project = Project(), id = project.languages[0].id
        let document = try OfficeDocumentImporter.parse(url: url, defaultLayerID: id)
        let sheet = try XCTUnwrap(document.sheets.first)
        XCTAssertEqual(sheet.name, "台詞"); XCTAssertEqual(sheet.suggestedHeader, 1)
        XCTAssertTrue(document.warnings.contains { $0.contains("cached") })
        var config = ImportConfiguration(defaultLayerID: id)
        config.columns = [0: .key, 2: .text(id)]
        let rows = try ImportMapping.rows(sheet: sheet, configuration: config, languages: project.languages)
        XCTAssertEqual(rows.map(\.key), ["stable-一", "stable-二"])
        XCTAssertEqual(rows[0].content.texts[id], "繁體台詞")
        XCTAssertEqual(rows[1].content.texts[id], "简体中文")
        config.columns[1] = .text(id)
        XCTAssertThrowsError(try ImportMapping.rows(sheet: sheet, configuration: config, languages: project.languages))
    }
    func testInvalidFormulaAndDTDRejected() throws {
        let id = UUID()
        let url = try workbook("<row r='1'><c r='A1'><f>1+1</f></c></row>")
        XCTAssertThrowsError(try OfficeDocumentImporter.parse(url: url, defaultLayerID: id))
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            let xml = "<?xml version='1.0'?><!DOCTYPE x [<!ENTITY y 'expanded'>]><x>&y;</x>"
            XCTAssertThrowsError(try OfficeXML.parse(try XCTUnwrap(xml.data(using: encoding))))
        }
    }
    func testWordHeadingsSpeakerTableAndFormatting() throws {
        let url = try archive(["word/document.xml": """
        <w:document xmlns:w="urn:word"><w:body>
        <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>第一幕</w:t></w:r></w:p>
        <w:p><w:pPr><w:pStyle w:val="Character"/></w:pPr><w:r><w:t>王子</w:t></w:r></w:p>
        <w:p><w:r><w:rPr><w:b/><w:i/><w:u w:val="single"/></w:rPr><w:t>你好</w:t><w:br/><w:t>世界</w:t></w:r></w:p>
        <w:tbl><w:tr><w:tc><w:p><w:r><w:t>公主：再見</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
        </w:body></w:document>
        """], extension: "docx")
        let id = UUID(), parsed = try OfficeDocumentImporter.parse(url: url, defaultLayerID: id)
        XCTAssertEqual(parsed.rows.count, 4)
        XCTAssertTrue(parsed.rows[0].ignored); XCTAssertTrue(parsed.rows[1].ignored)
        XCTAssertEqual(parsed.rows[2].content.speaker, "王子")
        XCTAssertEqual(parsed.rows[2].content.texts[id], "你好\n世界")
        XCTAssertEqual(parsed.rows[2].content.traits[id]?.bold, true)
        XCTAssertEqual(parsed.rows[3].content.speaker, "公主")
        XCTAssertEqual(parsed.rows[3].content.texts[id], "再見")
    }
    private func sample() throws -> (Project, ImportSource, DocumentImportRow) {
        let project = Project(), id = project.languages[0].id
        let source = ImportSource(name: "Script", kind: "xlsx", configuration: ImportConfiguration(defaultLayerID: id), hasStableKeys: true)
        var row = DocumentImportRow(); row.key = "external-1"; row.content.texts[id] = "Original"; row.content.number = "A1"
        let plan = try ImportDiff.plan(project: project, source: source, rows: [row], reimport: false)
        return (try ImportDiff.applying(plan, selectedKeys: [row.key], to: project, after: nil, liveCueID: nil), source, row)
    }
    func testReimportPreservesProductionAndFlagsLocalConflicts() throws {
        var (project, source, row) = try sample()
        let cueID = project.cues[0].id
        project.cues[0].note = "Stage manager note"
        project.cues[0].style.fontSize = 90
        project.cues[0].transition.fadeInEnabled = true
        project.cues[0].text = "Local rewrite"
        row.content.texts[project.languages[0].id] = "New source"
        let plan = try ImportDiff.plan(project: project, source: source, rows: [row], reimport: true)
        XCTAssertTrue(plan.items[0].conflict)
        XCTAssertEqual(plan.items[0].change, .modified)
        let updated = try ImportDiff.applying(plan, selectedKeys: [row.key], to: project, after: nil, liveCueID: nil)
        XCTAssertEqual(updated.cues[0].id, cueID)
        XCTAssertEqual(updated.cues[0].note, "Stage manager note")
        XCTAssertEqual(updated.cues[0].style, project.cues[0].style)
        XCTAssertEqual(updated.cues[0].transition, project.cues[0].transition)
        XCTAssertEqual(updated.cues[0].text, "New source")
        XCTAssertEqual(try ImportDiff.plan(project: updated, source: source, rows: [row], reimport: true).items[0].change, .unchanged)
        XCTAssertThrowsError(try ImportDiff.applying(plan, selectedKeys: [row.key], to: project, after: nil, liveCueID: cueID))
    }
    func testDeletionRequiresSelectionAndIgnoreProtectsCue() throws {
        let (project, source, row) = try sample()
        let plan = try ImportDiff.plan(project: project, source: source, rows: [], reimport: true)
        XCTAssertEqual(plan.items[0].change, .deleted)
        XCTAssertEqual(try ImportDiff.applying(plan, selectedKeys: [], to: project, after: nil, liveCueID: nil).cues, project.cues)
        XCTAssertTrue(try ImportDiff.applying(plan, selectedKeys: [row.key], to: project, after: nil, liveCueID: nil).cues.isEmpty)
        var ignored = row; ignored.ignored = true
        XCTAssertTrue(try ImportDiff.plan(project: project, source: source, rows: [ignored], reimport: true).items.isEmpty)
        XCTAssertThrowsError(try ImportDiff.plan(project: project, source: source, rows: [row, row], reimport: true))
    }
    func testSplitMergeAndMultilingualValidation() throws {
        var row = DocumentImportRow(); row.key = "K"
        let a = UUID(), b = UUID()
        row.content.texts = [a: "一\n二", b: "one\ntwo"]
        let split = try ImportWorkspaceEditing.split(row)
        XCTAssertEqual(split.map(\.key), ["K", "K#part2"])
        XCTAssertEqual(try ImportWorkspaceEditing.merge(split).content.texts, row.content.texts)
        row.content.texts[b] = "one"
        XCTAssertThrowsError(try ImportWorkspaceEditing.split(row))
    }
    func testCurrentFormatRoundTripAndEightMigration() throws {
        let (project, _, _) = try sample()
        let data = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: data), project)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["projectFormatVersion"] = 8; json.removeValue(forKey: "importSources")
        let migrated = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.projectFormatVersion, 12)
        XCTAssertTrue(migrated.importSources.isEmpty); XCTAssertNil(migrated.cues[0].importOrigin)
        try migrated.validate()
    }
    @MainActor func testAtomicCommitUndoAndStalePreview() throws {
        let store = ProjectStore(), baseline = store.project, session = store.sessionID
        var result = baseline; result.cues = [Cue(text: "Imported")]
        try store.commitImport(result, baseline: baseline, sessionID: session, affected: [])
        XCTAssertEqual(store.project.cues.count, 1)
        store.undo(); XCTAssertEqual(store.project, baseline)
        store.change { $0.name = "Changed" }
        XCTAssertThrowsError(try store.commitImport(result, baseline: baseline, sessionID: session, affected: []))
        XCTAssertEqual(store.project.name, "Changed")
    }
}

extension DocumentImportTests {
    @MainActor func testImportWorkspaceNativeSnapshot() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Desktop import snapshot") }
        _ = NSApplication.shared
        var input = Project()
        input.languages[0].name = "中文"
        input.languages.append(LanguageLayer(name: "English", frame: input.languages[0].frame))
        input.cues = [Cue(displayNumber: "1", text: "今晚，我們在這裡相遇。")]
        input.cues[0].translations[input.languages[1].id] = "Tonight we meet here."
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xlsx")
        try SpreadsheetExporter.data(project: input).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(); store.addCue()
        let request = DocumentImportRequest(url: url)
        let session = DocumentImportSession(request: request, store: store)
        session.load()
        for _ in 0..<3000 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(session.error); XCTAssertNotNil(session.plan)
        XCTAssertEqual(session.draftLanguages.map(\.name), ["中文", "English"])
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 1040, height: 740), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hosting = NSHostingView(rootView: DocumentImportView(store: store, request: request, preparedSession: session))
        window.contentView = hosting; window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(500))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("SubtitleStage-import-single-page.png"))
        XCTAssertGreaterThan(png.count, 10000)
    }
}

extension DocumentImportTests {
    func testTargetRoutingAndGeneratedKeysDoNotUseRowNumbers() throws {
        let project = Project(), id = project.languages[0].id
        var config = ImportConfiguration(defaultLayerID: id)
        config.headerRow = 0; config.columns = [0: .dialogue, 1: .target]
        let sheet = SpreadsheetSheet(name: "Script", rows: [SpreadsheetRow(number: 42, cells: [0: "字幕", 1: project.languages[0].name])])
        let rows = try ImportMapping.rows(sheet: sheet, configuration: config, languages: project.languages)
        XCTAssertEqual(rows[0].content.texts[id], "字幕")
        XCTAssertNotNil(UUID(uuidString: rows[0].key)); XCTAssertNotEqual(rows[0].key, "42")
        let bad = SpreadsheetSheet(name: "Script", rows: [SpreadsheetRow(number: 42, cells: [0: "字幕", 1: "missing"])])
        XCTAssertThrowsError(try ImportMapping.rows(sheet: bad, configuration: config, languages: project.languages))
    }
    func testUnchangedSourceDoesNotOverwriteLocalTextOrReorderCues() throws {
        var (project, source, row) = try sample()
        project.cues[0].text = "Local rehearsal edit"
        let untouched = Cue(displayNumber: "pre", text: "Unrelated")
        project.cues.insert(untouched, at: 0)
        let plan = try ImportDiff.plan(project: project, source: source, rows: [row], reimport: true)
        XCTAssertEqual(plan.items[0].change, .unchanged)
        XCTAssertEqual(try ImportDiff.applying(plan, selectedKeys: [row.key], to: project, after: nil, liveCueID: nil), project)
    }
    @MainActor func testDuplicateUnbindsSourceAndCommitRejectsNewLiveCue() throws {
        let (project, _, _) = try sample()
        let store = ProjectStore()
        store.change { $0 = project }
        store.playback.selectedCueID = project.cues[0].id
        store.duplicateSelectedCue()
        XCTAssertNil(store.selectedCue?.importOrigin)
        try store.project.validate()
        let baseline = store.project, sessionID = store.sessionID
        var result = baseline; result.cues[0].text = "Changed"
        store.playback.selectedCueID = project.cues[0].id
        store.go()
        XCTAssertThrowsError(try store.commitImport(result, baseline: baseline, sessionID: sessionID, affected: [project.cues[0].id]))
        XCTAssertEqual(store.project, baseline)
    }
}
