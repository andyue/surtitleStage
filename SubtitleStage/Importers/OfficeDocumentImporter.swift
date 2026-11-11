import Foundation

public enum OfficeDocumentImporter {
    public static func parse(url: URL, defaultLayerID: UUID) throws -> ParsedDocument {
        if url.pathExtension.lowercased() == "glypheo" { return try GlypheoImporter.parse(url: url) }
        let package = try OfficePackage(url: url)
        switch url.pathExtension.lowercased() {
        case "xlsx": return try spreadsheet(package)
        case "docx": return try word(package, layerID: defaultLayerID)
        default: throw ProjectError.invalid("Choose an XLSX or DOCX document. Legacy XLS/DOC and encrypted documents are not supported.")
        }
    }
    private static func spreadsheet(_ package: OfficePackage) throws -> ParsedDocument {
        let workbook = try OfficeXML.parse(package.read("xl/workbook.xml"))
        let rels = try OfficeXML.parse(package.read("xl/_rels/workbook.xml.rels"))
        var targets: [String: String] = [:]
        for rel in rels.children where rel.name == "Relationship" {
            if rel.attributes["TargetMode"] == "External" { continue }
            guard let id = rel.attributes["Id"], let target = rel.attributes["Target"], rel.attributes["Type"]?.hasSuffix("/worksheet") == true else { continue }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
            guard !path.split(separator: "/").contains("..") else { throw ProjectError.invalid("Unsupported worksheet relationship path.") }
            targets[id] = path.replacingOccurrences(of: "/./", with: "/")
        }
        var shared: [String] = []
        if package.entries.contains("xl/sharedStrings.xml") {
            let root = try OfficeXML.parse(package.read("xl/sharedStrings.xml"))
            shared = root.children.filter { $0.name == "si" }.map { node in
                node.children.filter { $0.name != "rPh" }.flatMap { $0.name == "t" ? [$0] : $0.descendants("t") }.map(\.allText).joined()
            }
        }
        var document = ParsedDocument(kind: "xlsx")
        let sheets = workbook.descendants("sheet")
        guard !sheets.isEmpty, sheets.count <= 50 else { throw ProjectError.invalid("Workbook must contain 1–50 worksheets.") }
        var cellCount = 0
        for sheet in sheets {
            try Task.checkCancellation()
            guard let name = sheet.attributes["name"], let id = sheet.attributes["id"], let path = targets[id] else { throw ProjectError.invalid("Worksheet relationship is missing.") }
            guard !document.sheets.contains(where: { $0.name == name }) else { throw ProjectError.invalid("Duplicate worksheet names.") }
            let root = try OfficeXML.parse(package.read(path))
            var rows: [SpreadsheetRow] = []
            var usedRows = Set<Int>()
            for row in root.child("sheetData")?.children ?? [] where row.name == "row" {
                let number = Int(row.attributes["r"] ?? "") ?? ((rows.last?.number ?? 0) + 1)
                guard number > 0, usedRows.insert(number).inserted, rows.count < 10_000 else { throw ProjectError.invalid("Worksheet rows are invalid or exceed 10,000 rows.") }
                var cells: [Int: String] = [:]
                var nextColumn = 0
                for cell in row.children where cell.name == "c" {
                    cellCount += 1
                    guard cellCount <= 200_000 else { throw ProjectError.invalid("Workbook exceeds 200,000 cells.") }
                    let column = try columnIndex(cell.attributes["r"], fallback: nextColumn)
                    nextColumn = column + 1
                    guard cells[column] == nil else { throw ProjectError.invalid("Duplicate worksheet cell.") }
                    let value = cell.child("v")?.allText
                    if cell.child("f") != nil {
                        guard value != nil else { throw ProjectError.invalid("Formula at \(name)!\(cell.attributes["r"] ?? "?") has no cached value. Recalculate and save it in Excel first.") }
                        document.warnings.append("Formulas use saved cached values; this app does not calculate formulas.")
                    }
                    switch cell.attributes["t"] {
                    case "s":
                        guard let index = Int(value ?? ""), shared.indices.contains(index) else { throw ProjectError.invalid("Invalid shared-string reference.") }
                        cells[column] = shared[index]
                    case "inlineStr": cells[column] = cell.child("is")?.descendants("t").map(\.allText).joined() ?? ""
                    case "e": throw ProjectError.invalid("Spreadsheet error at \(name)!\(cell.attributes["r"] ?? "?"): \(value ?? "unknown")")
                    case "b": cells[column] = value == "1" ? "TRUE" : "FALSE"
                    default: cells[column] = value ?? ""
                    }
                    if cell.attributes["s"] != nil, cell.attributes["t"] == nil, let value, Double(value) != nil {
                        document.warnings.append("Numeric/date cells use stored values, not Excel display formats. Store formatted cue IDs and dates as text if needed.")
                    }
                }
                if !cells.values.allSatisfy({ $0.isEmpty }) { rows.append(SpreadsheetRow(number: number, cells: cells)) }
            }
            if root.child("mergeCells") != nil { document.warnings.append("Merged cells use their anchor value only; covered cells remain blank.") }
            if sheet.attributes["state"] != nil { document.warnings.append("Workbook includes hidden sheets; select the intended worksheet explicitly.") }
            document.sheets.append(SpreadsheetSheet(name: name, rows: rows.sorted { $0.number < $1.number }))
        }
        document.warnings = Array(Set(document.warnings)).sorted()
        return document
    }
    private static func columnIndex(_ reference: String?, fallback: Int) throws -> Int {
        guard let reference else {
            guard fallback < 256 else { throw ProjectError.invalid("Import supports up to 256 columns per worksheet.") }
            return fallback
        }
        var value = 0
        for scalar in reference.uppercased().unicodeScalars.prefix(while: { (65...90).contains($0.value) }) {
            value = value * 26 + Int(scalar.value - 64)
            guard value <= 256 else { throw ProjectError.invalid("Import supports up to 256 columns per worksheet.") }
        }
        guard value > 0 else { throw ProjectError.invalid("Invalid spreadsheet cell reference.") }
        return value - 1
    }
    private static func word(_ package: OfficePackage, layerID: UUID) throws -> ParsedDocument {
        let root = try OfficeXML.parse(package.read("word/document.xml"))
        guard let body = root.child("body") else { throw ProjectError.invalid("Word document has no body.") }
        var styles: [String: OfficeNode] = [:]
        if package.entries.contains("word/styles.xml") {
            let parsed = try OfficeXML.parse(package.read("word/styles.xml"))
            for style in parsed.children where style.name == "style" {
                if let id = style.attributes["styleId"] { styles[id] = style }
            }
        }
        var document = ParsedDocument(kind: "docx")
        var speaker = ""
        func on(_ node: OfficeNode?) -> Bool? {
            guard let node else { return nil }
            return !["0", "false", "off", "none"].contains(node.attributes["val"] ?? "1")
        }
        func traits(_ properties: OfficeNode?, base: ImportTextTraits) -> ImportTextTraits {
            var result = base
            if let value = on(properties?.child("b")) { result.bold = value }
            if let value = on(properties?.child("i")) { result.italic = value }
            if let value = on(properties?.child("u")) { result.underline = value }
            return result
        }
        func styleTraits(_ id: String?, depth: Int = 0) -> ImportTextTraits {
            guard depth < 20, let id, let style = styles[id] else { return ImportTextTraits() }
            return traits(style.child("rPr"), base: styleTraits(style.child("basedOn")?.attributes["val"], depth: depth + 1))
        }
        func runText(_ node: OfficeNode) -> String {
            if node.name == "t" { return node.allText }
            if node.name == "tab" { return "\t" }
            if node.name == "br" || node.name == "cr" { return "\n" }
            if node.name == "del" || node.name == "instrText" { return "" }
            return node.children.map(runText).joined()
        }
        var paragraphNumber = 0
        func addParagraph(_ paragraph: OfficeNode, location: String) {
            paragraphNumber += 1
            let styleID = paragraph.child("pPr")?.child("pStyle")?.attributes["val"]
            let styleName = (styleID ?? "") + " " + (styleID.flatMap { styles[$0]?.child("name")?.attributes["val"] } ?? "")
            let isHeading = styleName.lowercased().contains("heading") || styleName.lowercased().contains("title") || paragraph.child("pPr")?.child("outlineLvl") != nil
            let base = traits(paragraph.child("pPr")?.child("rPr"), base: styleTraits(styleID))
            let runs = paragraph.descendants("r").filter { !runText($0).isEmpty }
            var text = runText(paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            var row = DocumentImportRow(); row.location = location; row.key = UUID().uuidString
            row.ignored = isHeading
            if isHeading { row.warnings.append("Heading: ignored by default; enable it to import.") }
            if styleName.lowercased().contains("character") || styleName.lowercased().contains("speaker") {
                speaker = text; row.ignored = true; row.warnings.append("Speaker paragraph: used for following dialogue; ignored by default.")
            } else if let separator = text.firstIndex(where: { $0 == ":" || $0 == "：" }), text.distance(from: text.startIndex, to: separator) <= 30 {
                let candidate = String(text[..<separator]).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty, !candidate.contains("\n") {
                    row.content.speaker = candidate
                    text = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                    row.warnings.append("Speaker inferred from colon; review before import.")
                }
            }
            if row.content.speaker == nil { row.content.speaker = speaker }
            row.content.texts[layerID] = text
            let values = runs.map { run in
                let properties = run.child("rPr")
                let characterStyle = properties?.child("rStyle")?.attributes["val"]
                let inherited = characterStyle == nil ? base : styleTraits(characterStyle)
                return traits(properties, base: inherited)
            }
            if let first = values.first, values.allSatisfy({ $0 == first }) { row.content.traits[layerID] = first }
            else if !values.isEmpty { row.warnings.append("Mixed run formatting is flattened; per-character styling is not supported.") }
            document.rows.append(row)
        }
        for element in body.children {
            try Task.checkCancellation()
            if element.name == "p" { addParagraph(element, location: "Paragraph \(paragraphNumber + 1)") }
            else if element.name == "tbl" {
                for (rowIndex, tr) in element.children.filter({ $0.name == "tr" }).enumerated() {
                    for (column, cell) in tr.children.filter({ $0.name == "tc" }).enumerated() {
                        for p in cell.descendants("p") { addParagraph(p, location: "Table row \(rowIndex + 1), cell \(column + 1)") }
                    }
                }
            } else if !element.descendants("p").isEmpty {
                document.warnings.append("Content controls are flattened into paragraphs.")
                for p in element.descendants("p") { addParagraph(p, location: "Paragraph \(paragraphNumber + 1)") }
            }
        }
        guard document.rows.count <= 10_000 else { throw ProjectError.invalid("Word import exceeds 10,000 paragraphs.") }
        if !root.descendants("del").isEmpty || !root.descendants("ins").isEmpty { document.warnings.append("Tracked changes are read as visible inserted text; deleted text is excluded. Review the preview.") }
        if !root.descendants("drawing").isEmpty { document.warnings.append("Images and drawings are not imported.") }
        document.warnings.append("Word imports body paragraphs and table-cell paragraphs. Headers, footers, comments, page layout and per-character styling are not imported.")
        document.warnings = Array(Set(document.warnings)).sorted()
        return document
    }
}
