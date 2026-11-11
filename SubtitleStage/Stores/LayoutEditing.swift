import Foundation
import SubtitleCore

extension ProjectStore {
    func resizeCanvas(width: Double, height: Double) {
        guard width.isFinite, height.isFinite, (1...32768).contains(width), (1...32768).contains(height) else { return }
        guard width.rounded() == width, height.rounded() == height else { return }
        let old = project.canvas
        guard old.width != width || old.height != height else { return }
        let sx = width / old.width, sy = height / old.height
        change { project in
            project.canvases[0].width = width
            project.canvases[0].height = height
            for index in project.languages.indices {
                project.languages[index].frame = Self.scaledFrame(project.languages[index].frame, sx: sx, sy: sy)
            }
            for outputIndex in project.outputs.indices {
                for regionIndex in project.outputs[outputIndex].regions.indices {
                    if project.outputs[outputIndex].regions[regionIndex].sourceCanvasID == old.id {
                        let f = project.outputs[outputIndex].regions[regionIndex].source
                        project.outputs[outputIndex].regions[regionIndex].source = Self.scaledFrame(f, sx: sx, sy: sy)
                            .bounded(to: PixelSize(width: width, height: height))
                    }
                }
                guard project.outputs[outputIndex].canvasID == old.id else { continue }
                for id in Array(project.outputs[outputIndex].languageLayouts.keys) {
                    guard var placement = project.outputs[outputIndex].languageLayouts[id] else { continue }
                    placement.frame = Self.scaledFrame(placement.frame, sx: sx, sy: sy)
                    project.outputs[outputIndex].languageLayouts[id] = placement
                }
            }
        }
    }
    private static func scaledFrame(_ frame: PixelFrame, sx: Double, sy: Double) -> PixelFrame {
        PixelFrame(x: frame.x * sx, y: frame.y * sy, width: max(1, frame.width * sx), height: max(1, frame.height * sy))
    }
    func setText(_ text: String, cueID: UUID, languageID: UUID) {
        change(historyGroup: "cue-text.\(cueID.uuidString).\(languageID.uuidString)") {
            $0.setText(text, cueID: cueID, languageID: languageID)
        }
    }
    @discardableResult
    func addLanguage() -> UUID {
        let canvas = project.canvas
        let language = LanguageLayer(name: "Surtitle \(project.languages.count + 1)", frame: PixelFrame(x: canvas.width * 0.05, y: canvas.height * 0.65, width: canvas.width * 0.9, height: canvas.height * 0.2))
        change { $0.languages.append(language) }
        for output in project.outputs { ensureOutputLayout(output.id) }
        return language.id
    }
    @discardableResult
    func duplicateLanguage(_ sourceID: UUID) -> UUID? {
        guard let sourceIndex = project.languages.firstIndex(where: { $0.id == sourceID }) else { return nil }
        let source = project.languages[sourceIndex]
        var copy = source
        copy.id = UUID()
        let baseName = "\(source.name) Copy"
        var name = baseName
        var suffix = 2
        while project.languages.contains(where: { $0.name == name }) {
            name = "\(baseName) \(suffix)"; suffix += 1
        }
        copy.name = name
        change { project in
            for index in project.cues.indices {
                let sourceText = sourceIndex == 0 ? project.cues[index].text : project.cues[index].translations[sourceID] ?? ""
                project.cues[index].translations[copy.id] = sourceText
                if let patch = project.cues[index].styleOverrides[sourceID] { project.cues[index].styleOverrides[copy.id] = patch }
            }
            for index in project.outputs.indices {
                project.outputs[index].languageLayouts[copy.id] = project.outputs[index].languageLayouts[sourceID] ?? LanguagePlacement(source)
            }
            project.languages.insert(copy, at: sourceIndex + 1)
        }
        selectedSurtitleID = copy.id
        return copy.id
    }
    func editLanguage(_ id: UUID, _ edit: (inout LanguageLayer) -> Void) {
        guard let index = project.languages.firstIndex(where: { $0.id == id }) else { return }
        change { edit(&$0.languages[index]) }
    }
    func setLanguageFrame(_ id: UUID, frame: PixelFrame, outputID: UUID? = nil) {
        let canvas = canvas(for: outputID)
        guard [frame.x, frame.y, frame.width, frame.height].allSatisfy(\.isFinite) else { return }
        let width = min(canvas.width, max(1, frame.width))
        let height = min(canvas.height, max(1, frame.height))
        let bounded = PixelFrame(x: min(max(0, frame.x), canvas.width - width), y: min(max(0, frame.y), canvas.height - height), width: width, height: height)
        editLayoutLanguage(id, outputID: outputID) { $0.frame = bounded }
    }
    func nudgeSelectedLayout(dx: Double, dy: Double) {
        guard let outputID = layoutOutputID, let languageID = selectedSurtitleID,
              let language = layoutLanguage(languageID, outputID: outputID) else { return }
        setLanguageFrame(languageID,
                         frame: language.frame.adjusted(dx: dx, dy: dy, resizing: false, canvas: canvas(for: outputID)),
                         outputID: outputID)
    }
    func layoutLanguage(_ id: UUID, outputID: UUID?) -> LanguageLayer? {
        guard let language = project.languages.first(where: { $0.id == id }) else { return nil }
        return LiveFrame(cue: selectedCue ?? Cue(), project: project).resolvedLanguage(language, for: outputID)
    }
    func editLayoutLanguage(_ id: UUID, outputID: UUID?, _ edit: (inout LanguageLayer) -> Void) {
        guard let outputID else { editLanguage(id, edit); return }
        guard let index = project.outputs.firstIndex(where: { $0.id == outputID }), var language = layoutLanguage(id, outputID: outputID) else { return }
        edit(&language)
        change { $0.outputs[index].languageLayouts[id] = LanguagePlacement(language) }
    }
    func ensureOutputLayout(_ id: UUID) {
        guard let index = project.outputs.firstIndex(where: { $0.id == id }) else { return }
        let missing = project.languages.filter { project.outputs[index].languageLayouts[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let frame = LiveFrame(cue: selectedCue ?? Cue(), project: project)
        let placements = missing.map { ($0.id, LanguagePlacement(frame.resolvedLanguage($0, for: id))) }
        change(recordHistory: false) { project in
            for (languageID, placement) in placements { project.outputs[index].languageLayouts[languageID] = placement }
        }
    }
    @discardableResult
    func addOutput(displayID: UInt32? = nil) -> UUID {
        if let displayID, project.outputs.contains(where: { $0.displayID == displayID }) { return project.outputs.first(where: { $0.displayID == displayID })!.id }
        let configuration = OutputConfiguration(name: "Output \(project.outputs.count + 1)", displayID: displayID, canvasID: project.canvas.id)
        change { $0.outputs.append(configuration) }
        ensureOutputLayout(configuration.id)
        return configuration.id
    }
    func renameOutput(_ id: UUID, to name: String) {
        guard let index = project.outputs.firstIndex(where: { $0.id == id }) else { return }
        change(historyGroup: "output-name.\(id.uuidString)") { $0.outputs[index].name = name }
    }
    func assignDisplay(_ displayID: UInt32?, to outputID: UUID) {
        guard let index = project.outputs.firstIndex(where: { $0.id == outputID }) else { return }
        if let displayID, project.outputs.contains(where: { $0.id != outputID && $0.displayID == displayID }) {
            errorMessage = "That display is already assigned to another output."
            return
        }
        change { $0.outputs[index].displayID = displayID }
    }
    // Removing a destination must never broaden an explicit route to all outputs.
    func removeOutput(_ id: UUID) {
        change { project in
            project.outputs.removeAll { $0.id == id }
            for index in project.languages.indices where project.languages[index].outputIDs.contains(id) {
                project.languages[index].outputIDs.removeAll { $0 == id }
                if project.languages[index].outputIDs.isEmpty { project.languages[index].isVisible = false }
            }
        }
    }
}
