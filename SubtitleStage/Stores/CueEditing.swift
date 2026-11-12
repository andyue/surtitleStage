import Foundation
import SubtitleCore

struct CueNumberPreview: Identifiable {
    let id: UUID
    let oldNumber: String
    let newNumber: String
}

extension ProjectStore {
    var checkedCues: [Cue] { project.cues.filter { checkedCueIDs.contains($0.id) } }

    func duplicateSelectedCue() {
        guard let source = selectedCue, let index = project.cues.firstIndex(where: { $0.id == source.id }) else { return }
        var copy = source
        copy.id = UUID()
        copy.importOrigin = nil
        change { $0.cues.insert(copy, at: index + 1) }
        playback.selectedCueID = copy.id
    }

    func deleteCheckedCues() {
        let ids = Set(checkedCues.map(\.id))
        guard !ids.isEmpty else { return }
        guard playback.liveCueID.map({ !ids.contains($0) }) ?? true else {
            errorMessage = "The selection contains the live cue. Nothing was deleted. Uncheck the live cue first."
            return
        }
        let index = project.cues.firstIndex { $0.id == playback.selectedCueID } ?? 0
        change { $0.cues.removeAll { ids.contains($0.id) } }
        if let selected = playback.selectedCueID, ids.contains(selected) {
            playback.selectedCueID = project.cues.isEmpty ? nil : project.cues[min(index, project.cues.count - 1)].id
        }
    }

    func numberPreview(ids: Set<UUID>, start: Int) -> [CueNumberPreview]? {
        let cues = project.cues.filter { ids.contains($0.id) }
        guard start >= 0, !cues.isEmpty, cues.count == ids.count,
              start <= Int.max - (cues.count - 1) else { return nil }
        return cues.enumerated().map { CueNumberPreview(id: $0.element.id, oldNumber: $0.element.displayNumber, newNumber: String(start + $0.offset)) }
    }

    func renumberCues(ids: Set<UUID>, start: Int) {
        guard let preview = numberPreview(ids: ids, start: start) else {
            errorMessage = "Cannot renumber: use a non-negative whole number within range and select existing cues."
            return
        }
        let numbers = Dictionary(uniqueKeysWithValues: preview.map { ($0.id, $0.newNumber) })
        guard preview.contains(where: { $0.oldNumber != $0.newNumber }) else { return }
        change { project in
            for index in project.cues.indices {
                if let number = numbers[project.cues[index].id] { project.cues[index].displayNumber = number }
            }
        }
    }
}
