import Foundation

/// Reads archive data only; never instantiates classes from the source document.
public enum GlypheoImporter {
    public static func parse(url: URL) throws -> ParsedDocument {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 64 * 1024 * 1024 else { throw ProjectError.invalid("Glypheo document exceeds 64 MB.") }
        return try parse(data: Data(contentsOf: url))
    }

    public static func parse(data: Data) throws -> ParsedDocument {
        guard data.count <= 64 * 1024 * 1024 else { throw ProjectError.invalid("Glypheo document exceeds 64 MB.") }
        // XML serialization exposes keyed-archive references as CF$UID dictionaries.
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        // Foundation turns CF$UID back into opaque UID objects when reading XML.
        // Rename only that XML key so references remain ordinary dictionaries.
        let readableXML = Data(String(decoding: xml, as: UTF8.self)
            .replacingOccurrences(of: "<key>CF$UID</key>", with: "<key>SubtitleStageArchiveReference</key>").utf8)
        guard let archive = try PropertyListSerialization.propertyList(from: readableXML, format: nil) as? [String: Any],
              archive["$archiver"] as? String == "NSKeyedArchiver",
              let objects = archive["$objects"] as? [Any], objects.count <= 500_000,
              let top = archive["$top"] as? [String: Any] else {
            throw ProjectError.invalid("Unsupported Glypheo archive.")
        }
        func object(_ ref: Any?) throws -> Any {
            guard let ref = ref as? [String: Any], let index = ref["SubtitleStageArchiveReference"] as? Int,
                  objects.indices.contains(index) else { throw ProjectError.invalid("Invalid Glypheo object reference.") }
            return objects[index]
        }
        func dictionary(_ ref: Any?) throws -> [String: Any] {
            guard let result = try object(ref) as? [String: Any] else { throw ProjectError.invalid("Invalid Glypheo object.") }
            return result
        }
        func array(_ ref: Any?) throws -> [Any] {
            guard let result = try dictionary(ref)["NS.objects"] as? [Any] else { throw ProjectError.invalid("Invalid Glypheo list.") }
            return result
        }
        func string(_ ref: Any?) throws -> String {
            let value = try object(ref)
            if let text = value as? String { return text }
            if let value = value as? [String: Any], let text = value["NS.string"] as? String { return text }
            throw ProjectError.invalid("Invalid Glypheo text.")
        }
        let root = try dictionary(top["root"])
        let tracks = try array(root["tracks"])
        guard !tracks.isEmpty, tracks.count <= 128 else { throw ProjectError.invalid("Glypheo must contain 1–128 tracks.") }
        var ids: [String] = [], headers: [Int: String] = [0: "Source ID", 1: "Cue Number", 2: "Group / Status"]
        for (index, ref) in tracks.enumerated() {
            let track = try dictionary(ref)
            let id = try string(track["identifier"])
            guard !ids.contains(id) else { throw ProjectError.invalid("Duplicate Glypheo track identifier.") }
            ids.append(id); headers[index + 3] = try string(track["name"])
        }
        var rows = [SpreadsheetRow(number: 1, cells: headers)]
        var keys = Set<String>()
        var disabled = 0
        for groupRef in try array(root["groups"]) {
            let group = try dictionary(groupRef)
            let name = try string(group["name"])
            for cueRef in try array(group["surtitles"]) {
                try Task.checkCancellation()
                guard rows.count <= 10_000 else { throw ProjectError.invalid("Glypheo import exceeds 10,000 cues.") }
                let cue = try dictionary(cueRef)
                guard let uid = cue["uid"] as? NSNumber else { throw ProjectError.invalid("Glypheo cue has no source ID.") }
                let key = uid.stringValue
                guard keys.insert(key).inserted else { throw ProjectError.invalid("Duplicate Glypheo cue ID.") }
                let enabled = cue["enable"] as? Bool ?? true
                if !enabled { disabled += 1 }
                var cells: [Int: String] = [0: key, 1: String(rows.count), 2: name + (enabled ? "" : " · Disabled in Glypheo")]
                let values = try dictionary(cue["trackSurtitles"])
                guard let refs = values["NS.objects"] as? [Any], let trackKeys = values["NS.keys"] as? [Any], refs.count == trackKeys.count else {
                    throw ProjectError.invalid("Invalid Glypheo track dictionary.")
                }
                var seen = Set<String>()
                for (trackKey, ref) in zip(trackKeys, refs) {
                    let id = try string(trackKey)
                    guard let column = ids.firstIndex(of: id), seen.insert(id).inserted else { throw ProjectError.invalid("Unknown or duplicate Glypheo track.") }
                    let textObject = try dictionary(ref)
                    let attributed = try dictionary(textObject["attributedString"])
                    cells[column + 3] = try string(attributed["NSString"])
                }
                rows.append(SpreadsheetRow(number: rows.count + 1, cells: cells, ignoredByDefault: !enabled))
            }
        }
        var document = ParsedDocument(kind: "glypheo")
        document.sheets = [SpreadsheetSheet(name: "Glypheo Cues", rows: rows)]
        document.warnings = ["Imports all groups in document order as plain text, preserving line breaks and track columns. Cue numbers are sequential. Group / status metadata is not imported by the default workflow.",
                             "Glypheo fonts, per-character styles, transitions, hierarchy, panels and output mapping are not imported. Review the target layout before playback.",
                             "Blank cues are ignored by default in the preview; enable them explicitly if required."]
        if disabled > 0 { document.warnings.append("\(disabled) disabled Glypheo cues are ignored by default and marked in Group / Status. Enable them in preview only if they should play.") }
        return document
    }
}
