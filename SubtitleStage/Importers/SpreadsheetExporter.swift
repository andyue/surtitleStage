import Foundation

/// Text-only cue-sheet interchange. Production settings remain in the .substage project.
public enum SpreadsheetExporter {
    public static func data(project: Project, template: Bool = false) throws -> Data {
        let count = template ? 1 : project.cues.count
        guard count <= 9999, project.languages.count + 4 <= 256,
              (count + 1) * (project.languages.count + 4) <= 199_000 else {
            throw ProjectError.invalid("This cue sheet exceeds the XLSX import limits. Export a smaller project.")
        }
        let headers = ["Source ID", "Cue Number", "Speaker", "Notes"] + project.languages.enumerated().map { "Text \($0.offset + 1): \($0.element.name)" }
        var rows = [headers]
        if template {
            rows.append(["example-001", "1", "角色 / Speaker", "範例列：請替換或刪除 / Replace or delete this example"] +
                        project.languages.map { _ in "範例台詞 / Example dialogue" })
        } else {
            rows += project.cues.map { cue in
                [cue.id.uuidString, cue.displayNumber, cue.speaker, cue.note] +
                    project.languages.map { project.text(for: cue, languageID: $0.id) }
            }
        }
        var guide = [
            ["SubtitleStage XLSX Guide / 匯入說明", "Mapping / 對應"],
            ["Import worksheet / 匯入工作表", "Cue Sheet"],
            ["Header row / 標題列", "1"],
            ["Source ID", "Stable source ID — keep unique and unchanged / 唯一且固定，不隨排序改變"],
            ["Cue Number", "Cue number — display only / 僅供顯示"],
            ["Speaker", "Speaker / Character"],
            ["Notes", "Notes"],
            ["Export scope / 匯出範圍", "Text only. Save .substage for formatting, transitions and output mapping / 完整設定請用 Save"],
            ["Identity / 識別", "Export uses Cue UUID as Source ID; it does not create or replace import bindings / 匯出不變更來源綁定"],
            ["First import / 首次匯入", "Choose Add New Cues for a new show, or Merge by Cue Number to fill existing rows / 新增或依編號合併；欄位可選 New Surtitle"],
            ["Merge / 合併", "Map Cue Number and target text columns. Matching numbers share one cue; 001 and 1 differ / 同編號共用一列，已有文字需確認取代"],
            ["Re-import / 再次匯入", "After first import, use File > Re-import for this source; keep Source ID unchanged / 首次匯入後選同來源更新"],
            ["Template / 範本", "Replace or delete the example row. Add rows with unique IDs / 替換或刪除範例，每列需唯一 ID"]
        ]
        guide += project.languages.enumerated().map { ["Text \($0.offset + 1): \($0.element.name)", "Text → \($0.element.name)"] }
        let parts = [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """,
            "xl/workbook.xml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Cue Sheet" sheetId="1" r:id="rId1"/><sheet name="Import Guide" sheetId="2" r:id="rId2"/></sheets></workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0" encoding="UTF-8"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/></Relationships>
            """,
            "xl/worksheets/sheet1.xml": try worksheet(rows),
            "xl/worksheets/sheet2.xml": try worksheet(guide)
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SubtitleStage-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (path, text) in parts {
            guard text.utf8.count <= 20_000_000 else { throw ProjectError.invalid("Exported worksheet exceeds the 20 MB import limit.") }
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let archive = directory.appendingPathComponent("export.xlsx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", archive.path] + parts.keys.sorted()
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ProjectError.invalid("The Excel file could not be packaged.") }
        return try Data(contentsOf: archive)
    }
    private static func worksheet(_ rows: [[String]]) throws -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetData>
        """
        for (rowIndex, row) in rows.enumerated() {
            try Task.checkCancellation()
            xml += "<row r=\"\(rowIndex + 1)\">"
            for (column, value) in row.enumerated() {
                guard value.utf16.count <= 32767 else { throw ProjectError.invalid("Row \(rowIndex + 1), column \(column + 1) exceeds Excel's 32,767-character cell limit.") }
                guard value.unicodeScalars.allSatisfy({ $0.value == 9 || $0.value == 10 || $0.value == 13 || (32...0xD7FF).contains($0.value) || (0xE000...0xFFFD).contains($0.value) || (0x10000...0x10FFFF).contains($0.value) }) else {
                    throw ProjectError.invalid("Row \(rowIndex + 1), column \(column + 1) contains a control character that Excel cannot preserve.")
                }
                let escaped = value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\r", with: "&#13;")
                xml += "<c r=\"\(columnName(column))\(rowIndex + 1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escaped)</t></is></c>"
            }
            xml += "</row>"
        }
        return xml + "</sheetData></worksheet>"
    }
    private static func columnName(_ index: Int) -> String {
        var number = index + 1, name = ""
        while number > 0 { number -= 1; name = String(UnicodeScalar(65 + number % 26)!) + name; number /= 26 }
        return name
    }
}
