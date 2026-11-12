import Foundation

public struct LiveFrame: Equatable, Sendable {
    public var cue: Cue
    public var canvas: CanvasDefinition
    public var languages: [LanguageLayer]
    public var canvases: [CanvasDefinition]
    public var outputs: [OutputConfiguration]
    public var outputLayouts: [UUID: [UUID: LanguagePlacement]]
    public init(cue: Cue, project: Project) {
        self.cue = cue; canvas = project.canvas; languages = project.languages
        canvases = project.canvases; outputs = project.outputs
        outputLayouts = Dictionary(uniqueKeysWithValues: project.outputs.map { ($0.id, $0.languageLayouts) })
    }
    public func text(for language: LanguageLayer) -> String {
        language.id == languages.first?.id ? cue.text : cue.translations[language.id] ?? ""
    }
    public func resolvedLanguage(_ language: LanguageLayer, for outputID: UUID?) -> LanguageLayer {
        if let outputID, let placement = outputLayouts[outputID]?[language.id] { return placement.applying(to: language) }
        var result = language
        if let outputID { result.isVisible = language.isVisible && (language.outputIDs.isEmpty || language.outputIDs.contains(outputID)) }
        return result
    }
    public func style(for language: LanguageLayer) -> TextStyle {
        let base = language.usesCueStyle ? cue.style : language.style
        return cue.styleOverrides[language.id]?.applying(to: base) ?? base
    }
    public func layers(for outputID: UUID?) -> [LanguageLayer] {
        languages.map { resolvedLanguage($0, for: outputID) }.filter(\.isVisible)
    }

}

public struct PlaybackState: Equatable, Sendable {
    public var selectedCueID: UUID?
    public private(set) var liveFrame: LiveFrame?
    public private(set) var isBlackout = false
    public private(set) var subtitleOpacity = 1.0
    public private(set) var masterOpacity = 1.0
    public private(set) var transitionDuration = 0.0
    public var visibleOpacity: Double { isBlackout ? 0 : subtitleOpacity * masterOpacity }
    public var liveCueID: UUID? { liveFrame?.cue.id }
    public init() {}

    // GO advances relative to LIVE, never an incidental editor selection.
    // Before first GO, the selected cue is the starting cue (or the first cue).
    public mutating func go(in project: Project) {
        guard !project.cues.isEmpty else { return }
        let index: Int
        if let liveCueID {
            guard let current = project.cues.firstIndex(where: { $0.id == liveCueID }), current + 1 < project.cues.count else { return }
            index = current + 1
        } else {
            index = project.cues.firstIndex(where: { $0.id == selectedCueID }) ?? 0
        }
        take(project.cues[index], project: project)
    }

    public mutating func previous(in project: Project) {
        guard let current = project.cues.firstIndex(where: { $0.id == liveCueID }), current > 0 else { return }
        take(project.cues[current - 1], project: project)
    }

    public mutating func showSelected(in project: Project) {
        guard let cue = project.cues.first(where: { $0.id == selectedCueID }) ?? project.cues.first else { return }
        take(cue, project: project)
    }

    public mutating func refreshLive(in project: Project) {
        guard let id = liveCueID, let cue = project.cues.first(where: { $0.id == id }) else { return }
        liveFrame = LiveFrame(cue: cue, project: project)
    }

    private mutating func take(_ cue: Cue, project: Project) {
        liveFrame = LiveFrame(cue: cue, project: project)
        subtitleOpacity = 1
        transitionDuration = 0
    }
    public mutating func fadeIn(duration: Double) {
        transitionDuration = duration; subtitleOpacity = 1
    }
    public mutating func fadeOut(duration: Double) {
        transitionDuration = duration; subtitleOpacity = 0
    }
    public mutating func prepareFadeIn() {
        transitionDuration = 0; subtitleOpacity = 0
    }
    public mutating func restoreSubtitleVisibility() {
        transitionDuration = 0; subtitleOpacity = 1
    }
    public mutating func setMasterOpacity(_ value: Double) {
        masterOpacity = min(1, max(0, value))
    }
    public mutating func toggleBlackout(duration: Double = 1) {
        transitionDuration = duration; isBlackout.toggle()
    }
    public mutating func blackout(duration: Double = 1) {
        transitionDuration = duration; isBlackout = true
    }
}
