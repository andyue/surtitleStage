import AppKit
import UniformTypeIdentifiers
import SubtitleCore

extension ProjectStore {
    var canUseDocumentFiles: Bool { !isBusy && !isExporting && documentRequest == nil }

    func chooseDocument(source: ImportSource? = nil) {
        guard canUseDocumentFiles else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = (source.map { [$0.kind] } ?? ["xlsx", "docx", "glypheo"]).compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        documentRequest = DocumentImportRequest(url: url, source: source)
    }

    func exportSpreadsheet(template: Bool) async {
        guard canUseDocumentFiles else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]
        panel.nameFieldStringValue = template ? "SubtitleStage-Import-Template.xlsx" : "SubtitleStage-Cue-Sheet.xlsx"
        panel.message = template ? "Includes an example row and an Import Guide worksheet." : "Exports cue text and metadata, plus an Import Guide. Use Save for full project settings."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let snapshot = project
        isExporting = true
        defer { isExporting = false }
        do {
            try await Task.detached(priority: .userInitiated) {
                let data = try SpreadsheetExporter.data(project: snapshot, template: template)
                try data.write(to: url, options: .atomic)
            }.value
        } catch { errorMessage = "Excel export failed: " + error.localizedDescription }
    }
}
