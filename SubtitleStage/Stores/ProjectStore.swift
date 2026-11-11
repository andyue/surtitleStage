import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SubtitleCore

@MainActor
final class ProjectStore: ObservableObject {
    private struct HistoryEntry {
        var project: Project
        var selectedCueID: UUID?
        var selectedSurtitleID: UUID?
        var checkedCueIDs: Set<UUID>
    }
    @Published private(set) var project: Project
    @Published private(set) var sessionID = UUID()
    @Published var playback = PlaybackState()
    @Published var checkedCueIDs: Set<UUID> = []
    @Published var selectedSurtitleID: UUID?
    @Published var layoutOutputID: UUID?
    @Published private(set) var fileURL: URL?
    @Published private(set) var isDirty = false
    @Published private(set) var isBusy = false
    @Published private(set) var isCueTransitioning = false
    @Published var documentRequest: DocumentImportRequest?
    @Published var isExporting = false
    @Published var errorMessage: String?
    private var revision = 0
    private var savedProject: Project
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []
    private var activeHistoryGroup: String?
    private let historyLimit = 100
    private var cueTransitionTask: Task<Void, Never>?

    private enum NavigationDirection { case next, previous }

    init() {
        let initial = Project()
        project = initial
        savedProject = initial
        selectedSurtitleID = initial.languages.first?.id
    }

    var selectedCue: Cue? { project.cues.first { $0.id == playback.selectedCueID } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func change(recordHistory: Bool = true, historyGroup: String? = nil, _ body: (inout Project) -> Void) {
        if recordHistory {
            if historyGroup == nil || historyGroup != activeHistoryGroup {
                undoStack.append(historyEntry())
                if undoStack.count > historyLimit { undoStack.removeFirst(undoStack.count - historyLimit) }
            }
            activeHistoryGroup = historyGroup
            redoStack.removeAll(keepingCapacity: true)
        }
        body(&project)
        checkedCueIDs.formIntersection(Set(project.cues.map(\.id)))
        playback.refreshLive(in: project)
        revision += 1
        isDirty = project != savedProject
    }
    func undo(outputRunning: Bool = false) {
        guard let target = undoStack.last else { return }
        guard canRestore(target, outputRunning: outputRunning) else { return }
        cancelCueTransition()
        undoStack.removeLast()
        activeHistoryGroup = nil
        redoStack.append(historyEntry())
        restore(target)
    }
    func redo(outputRunning: Bool = false) {
        guard let target = redoStack.last else { return }
        guard canRestore(target, outputRunning: outputRunning) else { return }
        cancelCueTransition()
        redoStack.removeLast()
        activeHistoryGroup = nil
        undoStack.append(historyEntry())
        restore(target)
    }
    func endHistoryGroup() { activeHistoryGroup = nil }
    private func historyEntry() -> HistoryEntry {
        HistoryEntry(project: project, selectedCueID: playback.selectedCueID, selectedSurtitleID: selectedSurtitleID, checkedCueIDs: checkedCueIDs)
    }
    private func canRestore(_ entry: HistoryEntry, outputRunning: Bool) -> Bool {
        if let liveID = playback.liveCueID, !entry.project.cues.contains(where: { $0.id == liveID }) {
            errorMessage = "Cannot undo while that cue is live. Take another cue first."
            return false
        }
        if outputRunning, Set(entry.project.outputs.map(\.id)) != Set(project.outputs.map(\.id)) {
            errorMessage = "Stop Output before undoing an output-slot change."
            return false
        }
        if outputRunning {
            for config in project.outputs {
                guard let old = entry.project.outputs.first(where: { $0.id == config.id }) else { continue }
                if old.displayID != config.displayID || old.resolution != config.resolution || old.isEnabled != config.isEnabled || old.canvasID != config.canvasID || old.scaleMode != config.scaleMode || old.regions != config.regions {
                    errorMessage = "Stop Output before undoing an output mapping or device configuration change."
                    return false
                }
            }
        }
        return true
    }
    private func restore(_ entry: HistoryEntry) {
        project = entry.project
        checkedCueIDs = entry.checkedCueIDs.intersection(Set(project.cues.map(\.id)))
        playback.selectedCueID = entry.selectedCueID.flatMap { id in project.cues.contains(where: { $0.id == id }) ? id : nil } ?? project.cues.first?.id
        selectedSurtitleID = entry.selectedSurtitleID.flatMap { id in project.languages.contains(where: { $0.id == id }) ? id : nil } ?? project.languages.first?.id
        if let layoutOutputID, !project.outputs.contains(where: { $0.id == layoutOutputID }) { self.layoutOutputID = nil }
        playback.refreshLive(in: project)
        revision += 1
        isDirty = project != savedProject
    }
    func editCue(_ cue: Cue) {
        guard let index = project.cues.firstIndex(where: { $0.id == cue.id }) else { return }
        change { $0.cues[index] = cue }
    }
    func addCue() {
        let cue = Cue(displayNumber: String(project.cues.count + 1))
        change { $0.cues.append(cue) }; playback.selectedCueID = cue.id
    }
    @discardableResult
    func addCue(after cueID: UUID, focusing languageID: UUID) -> UUID {
        let cue = Cue(displayNumber: String(project.cues.count + 1))
        change { project in
            let index = project.cues.firstIndex(where: { $0.id == cueID }).map { $0 + 1 } ?? project.cues.count
            project.cues.insert(cue, at: index)
        }
        playback.selectedCueID = cue.id
        selectedSurtitleID = languageID
        return cue.id
    }
    func deleteCue() {
        guard let id = playback.selectedCueID, let index = project.cues.firstIndex(where: { $0.id == id }) else { return }
        guard id != playback.liveCueID else {
            errorMessage = "The live cue cannot be deleted. Advance to another cue first."; return
        }
        change { $0.cues.remove(at: index) }
        playback.selectedCueID = project.cues.isEmpty ? nil : project.cues[min(index, project.cues.count - 1)].id
    }
    func deleteCue(id: UUID) {
        playback.selectedCueID = id
        deleteCue()
    }
    func moveCue(by offset: Int) {
        guard let id = playback.selectedCueID,
              let source = project.cues.firstIndex(where: { $0.id == id }),
              project.cues.indices.contains(source + offset) else { return }
        change { $0.moveCue(id: id, by: offset) }
    }
    func moveCue(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let source = project.cues.firstIndex(where: { $0.id == id }),
              let target = project.cues.firstIndex(where: { $0.id == targetID }) else { return }
        change { project in
            let cue = project.cues.remove(at: source)
            let destination = target
            project.cues.insert(cue, at: destination)
        }
        playback.selectedCueID = id
    }
    func importItems(_ items: [ImportItem]) {
        guard let languageID = project.languages.first?.id else { return }
        importItems(items, to: languageID, after: playback.selectedCueID)
    }
    func importItems(_ items: [ImportItem], to languageID: UUID, after cueID: UUID?) {
        guard !items.isEmpty, project.languages.contains(where: { $0.id == languageID }) else { return }
        let start = project.cues.count
        var cues = items.enumerated().map { Cue(displayNumber: String(start + $0.offset + 1)) }
        for index in cues.indices {
            if languageID == project.languages.first?.id { cues[index].text = items[index].text }
            else { cues[index].translations[languageID] = items[index].text }
        }
        change { project in
            let insertion = cueID.flatMap { id in project.cues.firstIndex(where: { $0.id == id }) }.map { $0 + 1 } ?? project.cues.count
            project.cues.insert(contentsOf: cues, at: insertion)
        }
        playback.selectedCueID = cues.first?.id
        selectedSurtitleID = languageID
    }
    func go() { navigate(.next) }
    func previous() { navigate(.previous) }
    func showSelectedCue() {
        cancelCueTransition()
        playback.showSelected(in: project)
        applyFadeInIfNeeded()
    }
    func adjustMasterOpacity(by amount: Double) {
        playback.setMasterOpacity(playback.masterOpacity + amount)
    }
    func toggleBlackout() {
        cancelCueTransition()
        playback.restoreSubtitleVisibility()
        playback.toggleBlackout(duration: project.transitions.blackoutFadeDuration)
    }
    func blackout() {
        cancelCueTransition()
        playback.restoreSubtitleVisibility()
        playback.blackout(duration: project.transitions.blackoutFadeDuration)
    }
    func editCueTransition(_ cueID: UUID, _ edit: (inout CueTransition) -> Void) {
        guard let index = project.cues.firstIndex(where: { $0.id == cueID }) else { return }
        change { edit(&$0.cues[index].transition) }
    }
    private func navigate(_ direction: NavigationDirection) {
        guard !isCueTransitioning, canNavigate(direction) else { return }
        let transition = playback.liveFrame?.cue.transition
        let fadeOutDuration = transition?.fadeOutEnabled == true ? transition?.fadeOutDuration ?? 0 : 0
        guard fadeOutDuration > 0, playback.liveFrame != nil, !playback.isBlackout else {
            take(direction); return
        }
        isCueTransitioning = true
        playback.fadeOut(duration: fadeOutDuration)
        cueTransitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(fadeOutDuration))
            guard !Task.isCancelled, let self else { return }
            self.take(direction)
            self.isCueTransitioning = false
            self.cueTransitionTask = nil
        }
    }
    private func canNavigate(_ direction: NavigationDirection) -> Bool {
        switch direction {
        case .next:
            guard let liveID = playback.liveCueID else { return !project.cues.isEmpty }
            guard let index = project.cues.firstIndex(where: { $0.id == liveID }) else { return false }
            return index + 1 < project.cues.count
        case .previous:
            guard let liveID = playback.liveCueID,
                  let index = project.cues.firstIndex(where: { $0.id == liveID }) else { return false }
            return index > 0
        }
    }
    private func take(_ direction: NavigationDirection) {
        switch direction {
        case .next: playback.go(in: project)
        case .previous: playback.previous(in: project)
        }
        applyFadeInIfNeeded()
    }
    private func applyFadeInIfNeeded() {
        guard let cue = playback.liveFrame?.cue, cue.transition.fadeInEnabled, cue.transition.fadeInDuration > 0 else { return }
        let cueID = cue.id
        let duration = cue.transition.fadeInDuration
        playback.prepareFadeIn()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.playback.liveCueID == cueID else { return }
            self.playback.fadeIn(duration: duration)
        }
    }
    private func cancelCueTransition() {
        cueTransitionTask?.cancel(); cueTransitionTask = nil; isCueTransitioning = false
    }

    func mayDiscard() async -> Bool {
        guard !isBusy else { return false }
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(project.name)?"
        alert.informativeText = "Unsaved changes will be lost if you discard them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return await save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    func newProject() async {
        guard await mayDiscard() else { return }
        replace(with: Project(), url: nil)
    }
    func openProject() async {
        guard await mayDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(exportedAs: "local.SubtitleStage.project", conformingTo: .json), .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let loaded = try await Task.detached { try ProjectCodec.load(from: url) }.value
            replace(with: loaded, url: url)
        } catch { errorMessage = "Project cannot be opened. \(error.localizedDescription)" }
    }
    @discardableResult
    func save(as saveAs: Bool = false) async -> Bool {
        guard !isBusy else { return false }
        var target = fileURL
        if saveAs || target == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(exportedAs: "local.SubtitleStage.project", conformingTo: .json)]
            panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.substage"
            guard panel.runModal() == .OK else { return false }
            target = panel.url
        }
        guard let target else { return false }
        let snapshot = project
        let savedRevision = revision
        isBusy = true
        defer { isBusy = false }
        do {
            try await Task.detached { try ProjectCodec.save(snapshot, to: target) }.value
            fileURL = target
            if revision == savedRevision { savedProject = snapshot; isDirty = false }
            return !isDirty
        } catch {
            errorMessage = "Project cannot be saved. \(error.localizedDescription)"
            return false
        }
    }
    private func replace(with project: Project, url: URL?) {
        cancelCueTransition()
        self.project = project; fileURL = url; sessionID = UUID()
        savedProject = project
        undoStack.removeAll(); redoStack.removeAll()
        activeHistoryGroup = nil
        checkedCueIDs = []
        selectedSurtitleID = project.languages.first?.id
        playback = PlaybackState(); playback.selectedCueID = project.cues.first?.id
        revision += 1; isDirty = false
    }
}
