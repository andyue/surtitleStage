import Foundation
import SubtitleCore

extension ProjectStore {
    /// The first layer uses legacy cue.text storage. Preserve identity when it moves.
    private static func rebasePrimary(in project: inout Project, from oldID: UUID) {
        guard let newID = project.languages.first?.id, newID != oldID else { return }
        for i in project.cues.indices {
            let newText = project.cues[i].translations.removeValue(forKey: newID) ?? ""
            project.cues[i].translations[oldID] = project.cues[i].text
            project.cues[i].text = newText
        }
    }

    @discardableResult
    func moveSurtitle(id: UUID, to targetID: UUID?) -> Bool {
        guard !isBusy, let oldPrimary = project.languages.first?.id,
              let source = project.languages.firstIndex(where: { $0.id == id }), id != targetID,
              targetID == nil || project.languages.contains(where: { $0.id == targetID }) else { return false }
        var order = project.languages
        let layer = order.remove(at: source)
        let insertion = targetID.flatMap { target in project.languages.firstIndex { $0.id == target } } ?? order.count
        order.insert(layer, at: insertion)
        guard order != project.languages else { return false }
        change {
            $0.languages = order
            Self.rebasePrimary(in: &$0, from: oldPrimary)
        }
        return true
    }

    func moveSurtitle(id: UUID, by offset: Int) {
        guard let index = project.languages.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard project.languages.indices.contains(target) else { return }
        moveSurtitle(id: id, to: project.languages[target].id)
    }

    func deleteSurtitle(id: UUID) {
        guard !isBusy, project.languages.count > 1, project.languages.contains(where: { $0.id == id }),
              let oldPrimary = project.languages.first?.id else { return }
        change { project in
            project.languages.removeAll { $0.id == id }
            Self.rebasePrimary(in: &project, from: oldPrimary)
            for i in project.cues.indices {
                project.cues[i].translations.removeValue(forKey: id)
                project.cues[i].styleOverrides.removeValue(forKey: id)
                project.cues[i].importOrigin?.baseline.texts.removeValue(forKey: id)
                project.cues[i].importOrigin?.baseline.traits.removeValue(forKey: id)
            }
            for i in project.outputs.indices { project.outputs[i].languageLayouts.removeValue(forKey: id) }
            for i in project.importSources.indices {
                let columns = project.importSources[i].configuration.columns
                for (column, role) in columns where role == .text(id) {
                    project.importSources[i].configuration.columns[column] = .ignore
                }
                if project.importSources[i].configuration.defaultLayerID == id {
                    project.importSources[i].configuration.defaultLayerID = project.languages[0].id
                }
            }
        }
        if selectedSurtitleID == id { selectedSurtitleID = project.languages.first?.id }
    }
}
