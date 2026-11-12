import Foundation

public struct CanvasDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var width: Double
    public var height: Double
    // V0.1 default preset; rendering never assumes this resolution.
    public init(width: Double = 1920, height: Double = 1080) {
        self.width = width; self.height = height
    }
}

public enum TextAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

public struct TransitionSettings: Codable, Equatable, Sendable {
    public var subtitleFadeDuration: Double
    public var blackoutFadeDuration: Double
    public init(subtitleFadeDuration: Double = 0.5, blackoutFadeDuration: Double = 1) {
        self.subtitleFadeDuration = subtitleFadeDuration
        self.blackoutFadeDuration = blackoutFadeDuration
    }
}

public struct CueTransition: Codable, Equatable, Sendable {
    public var fadeInEnabled: Bool
    public var fadeInDuration: Double
    public var fadeOutEnabled: Bool
    public var fadeOutDuration: Double
    public init(fadeInEnabled: Bool = false, fadeInDuration: Double = 0.5,
                fadeOutEnabled: Bool = false, fadeOutDuration: Double = 0.5) {
        self.fadeInEnabled = fadeInEnabled; self.fadeInDuration = fadeInDuration
        self.fadeOutEnabled = fadeOutEnabled; self.fadeOutDuration = fadeOutDuration
    }
}

public struct Cue: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayNumber: String
    public var name: String
    public var note: String
    public var speaker = ""
    public var importOrigin: CueImportOrigin?
    public var text: String
    public var style: TextStyle
    public var translations: [UUID: String] = [:]
    public var styleOverrides: [UUID: TextStylePatch] = [:]
    public var transition = CueTransition()
    public init(id: UUID = UUID(), displayNumber: String = "", name: String = "", note: String = "", text: String = "", style: TextStyle = TextStyle()) {
        self.id = id; self.displayNumber = displayNumber; self.name = name
        self.note = note; self.text = text; self.style = style
    }
}

extension Cue {
    private enum CodingKeys: String, CodingKey { case id, displayNumber, name, note, speaker, importOrigin, text, style, translations, styleOverrides, transition }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayNumber = try c.decode(String.self, forKey: .displayNumber)
        name = try c.decode(String.self, forKey: .name)
        note = try c.decode(String.self, forKey: .note)
        speaker = try c.decodeIfPresent(String.self, forKey: .speaker) ?? ""
        importOrigin = try c.decodeIfPresent(CueImportOrigin.self, forKey: .importOrigin)
        text = try c.decode(String.self, forKey: .text)
        style = try c.decode(TextStyle.self, forKey: .style)
        styleOverrides = try c.decodeIfPresent([UUID: TextStylePatch].self, forKey: .styleOverrides) ?? [:]
        translations = try c.decodeIfPresent([UUID: String].self, forKey: .translations) ?? [:]
        transition = try c.decodeIfPresent(CueTransition.self, forKey: .transition) ?? CueTransition()
    }
}

public struct OutputConfiguration: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var name: String
    public var displayID: UInt32?
    public var canvasID: UUID
    public var languageLayouts: [UUID: LanguagePlacement] = [:]
    public var resolution: PixelSize? = nil
    public var isEnabled = true
    public var scaleMode: ScaleMode = .fit
    public var regions: [OutputRegion] = []
    public var syphon = SyphonSettings()
    public var ndi = NDISettings()
    public init(name: String = "", displayID: UInt32? = nil, canvasID: UUID) {
        self.name = name; self.displayID = displayID; self.canvasID = canvasID
    }
}

extension OutputConfiguration {
    private enum CodingKeys: String, CodingKey { case id, name, displayID, canvasID, languageLayouts, resolution, isEnabled, scaleMode, regions, syphon, ndi }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        displayID = try c.decodeIfPresent(UInt32.self, forKey: .displayID)
        canvasID = try c.decode(UUID.self, forKey: .canvasID)
        languageLayouts = try c.decodeIfPresent([UUID: LanguagePlacement].self, forKey: .languageLayouts) ?? [:]
        resolution = try c.decodeIfPresent(PixelSize.self, forKey: .resolution)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        scaleMode = try c.decodeIfPresent(ScaleMode.self, forKey: .scaleMode) ?? .fit
        regions = try c.decodeIfPresent([OutputRegion].self, forKey: .regions) ?? []
        syphon = try c.decodeIfPresent(SyphonSettings.self, forKey: .syphon) ?? SyphonSettings()
        ndi = try c.decodeIfPresent(NDISettings.self, forKey: .ndi) ?? NDISettings()
    }
}

public struct Project: Codable, Equatable, Sendable {
    public var projectFormatVersion = 12
    public var name = "Untitled"
    public var canvases: [CanvasDefinition] = [CanvasDefinition()]
    public var cues: [Cue] = []
    public var outputs: [OutputConfiguration] = []
    public var languages: [LanguageLayer]
    public var importSources: [ImportSource] = []
    public var transitions = TransitionSettings()
    public init() { languages = [.primary(canvas: canvases[0])] }

    private enum CodingKeys: String, CodingKey { case projectFormatVersion, name, canvases, cues, outputs, languages, transitions, importSources }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .projectFormatVersion)
        guard (1...12).contains(version) else { throw ProjectError.invalid("Unsupported project format version \(version).") }
        name = try c.decode(String.self, forKey: .name)
        canvases = try c.decode([CanvasDefinition].self, forKey: .canvases)
        cues = try c.decode([Cue].self, forKey: .cues)
        outputs = try c.decode([OutputConfiguration].self, forKey: .outputs)
        if version == 1 {
            guard let canvas = canvases.first else { throw ProjectError.invalid("Project has no canvas.") }
            var legacy = LanguageLayer.primary(canvas: canvas)
            legacy.frame = PixelFrame(x: canvas.width * 0.05, y: 0, width: canvas.width * 0.9, height: canvas.height)
            languages = [legacy]
        } else { languages = try c.decode([LanguageLayer].self, forKey: .languages) }
        transitions = try c.decodeIfPresent(TransitionSettings.self, forKey: .transitions) ?? TransitionSettings()
        // Explicit v1–7 migration: retain full-canvas Fit and automatic display size.
        if version < 8 {
            for index in outputs.indices {
                outputs[index].resolution = nil
                outputs[index].isEnabled = true
                outputs[index].scaleMode = .fit
                outputs[index].regions = []
            }
        }
        importSources = version >= 9 ? try c.decode([ImportSource].self, forKey: .importSources) : []
        if version < 9 { for index in cues.indices { cues[index].importOrigin = nil } }
        if version < 10 { for index in outputs.indices { outputs[index].syphon = SyphonSettings() } }
        if version < 11 { for index in outputs.indices { outputs[index].ndi = NDISettings() } }
        // v12 expands permitted layout coordinates and line spacing; v1–11 values remain unchanged.
        projectFormatVersion = 12
    }
    public func text(for cue: Cue, languageID: UUID) -> String {
        languageID == languages.first?.id ? cue.text : cue.translations[languageID] ?? ""
    }
    public mutating func setText(_ text: String, cueID: UUID, languageID: UUID) {
        guard let index = cues.firstIndex(where: { $0.id == cueID }), languages.contains(where: { $0.id == languageID }) else { return }
        if languageID == languages.first?.id { cues[index].text = text }
        else { cues[index].translations[languageID] = text }
    }
    public var canvas: CanvasDefinition { canvases[0] }

    public func validate() throws {
        guard projectFormatVersion == 12 else { throw ProjectError.invalid("Unsupported project format version \(projectFormatVersion).") }
        guard transitions.subtitleFadeDuration.isFinite, (0...10).contains(transitions.subtitleFadeDuration),
              transitions.blackoutFadeDuration.isFinite, (0...10).contains(transitions.blackoutFadeDuration) else {
            throw ProjectError.invalid("Fade durations must be between 0 and 10 seconds.")
        }
        guard !canvases.isEmpty, Set(canvases.map(\.id)).count == canvases.count else { throw ProjectError.invalid("Project must contain uniquely identified canvases.") }
        for canvas in canvases {
            guard canvas.width.isFinite, canvas.height.isFinite,
                  (1...32768).contains(canvas.width), (1...32768).contains(canvas.height),
                  canvas.width.rounded() == canvas.width, canvas.height.rounded() == canvas.height else {
                throw ProjectError.invalid("Canvas dimensions must be whole pixels between 1 and 32768.")
            }
        }
        guard Set(cues.map(\.id)).count == cues.count else { throw ProjectError.invalid("Duplicate cue UUIDs.") }
        let assignedDisplays = outputs.compactMap(\.displayID)
        guard Set(outputs.map(\.id)).count == outputs.count,
              Set(assignedDisplays).count == assignedDisplays.count,
              outputs.allSatisfy({ output in canvases.contains { $0.id == output.canvasID } }) else {
            throw ProjectError.invalid("Invalid output canvas assignment.")
        }
        guard !languages.isEmpty, Set(languages.map(\.id)).count == languages.count else {
            throw ProjectError.invalid("Project must contain uniquely identified languages.")
        }
        for language in languages {
            let f = language.frame
            guard [f.x, f.y, f.width, f.height, language.rotation.x, language.rotation.y, language.rotation.z].allSatisfy(\.isFinite), abs(f.x) <= 32768, abs(f.y) <= 32768,
                  f.width >= 1, f.height >= 1, f.width <= 32768, f.height <= 32768,
                  language.outputIDs.allSatisfy({ id in outputs.contains { $0.id == id } }) else {
                throw ProjectError.invalid("Invalid language layout or output assignment.")
            }
            try Self.validateStyle(language.style)
        }
        for output in outputs {
            try output.syphon.validate()
            try output.ndi.validate()
            try output.validateMapping(canvases: canvases)
            for (id, placement) in output.languageLayouts {
                let f = placement.frame
                guard languages.contains(where: { $0.id == id }),
                      [f.x, f.y, f.width, f.height, placement.rotation.x, placement.rotation.y, placement.rotation.z].allSatisfy(\.isFinite),
                      abs(f.x) <= 32768, abs(f.y) <= 32768, f.width >= 1, f.height >= 1,
                      f.width <= 32768, f.height <= 32768 else {
                    throw ProjectError.invalid("Invalid output language layout.")
                }
                try Self.validateStyle(placement.style)
            }
        }
        guard Set(importSources.map(\.id)).count == importSources.count else { throw ProjectError.invalid("Duplicate import source IDs.") }
        var bindings = Set<String>()
        for cue in cues {
            if let origin = cue.importOrigin {
                guard importSources.contains(where: { $0.id == origin.sourceID }), !origin.key.isEmpty,
                      bindings.insert(origin.sourceID.uuidString + ":" + origin.key).inserted else {
                    throw ProjectError.invalid("Invalid or duplicate import binding.")
                }
            }
            try Self.validateStyle(cue.style)
            guard cue.transition.fadeInDuration.isFinite, (0...10).contains(cue.transition.fadeInDuration),
                  cue.transition.fadeOutDuration.isFinite, (0...10).contains(cue.transition.fadeOutDuration) else {
                throw ProjectError.invalid("Cue fade durations must be between 0 and 10 seconds.")
            }
            for (id, patch) in cue.styleOverrides {
                guard languages.contains(where: { $0.id == id }) else { throw ProjectError.invalid("Unknown surtitle style assignment.") }
                try Self.validateStyle(patch.applying(to: TextStyle()))
            }
        }
    }
    private static func validateStyle(_ s: TextStyle) throws {
        guard s.color.isValid, s.fontSize.isFinite, (1...2048).contains(s.fontSize),
              s.characterSpacing.isFinite, (-100...1000).contains(s.characterSpacing),
              s.lineSpacing.isFinite, (-2048...2048).contains(s.lineSpacing) else {
            throw ProjectError.invalid("Invalid text formatting.")
        }
    }

    public mutating func moveCue(id: UUID, by offset: Int) {
        guard let source = cues.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard cues.indices.contains(destination) else { return }
        let cue = cues.remove(at: source)
        cues.insert(cue, at: destination)
    }
}

public enum ProjectError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): message } }
}
