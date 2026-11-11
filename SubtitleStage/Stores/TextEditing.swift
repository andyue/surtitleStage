import Foundation
import SubtitleCore

extension ProjectStore {
    func textStyle(cue: Cue, surtitleID: UUID) -> TextStyle {
        guard let layer = project.languages.first(where: { $0.id == surtitleID }) else { return cue.style }
        return LiveFrame(cue: cue, project: project).style(for: layer)
    }
    func modifyTextStyle(cueID: UUID, surtitleID: UUID, property: TextProperty, style: TextStyle, batch: Bool = false) {
        guard project.languages.contains(where: { $0.id == surtitleID }), project.cues.contains(where: { $0.id == cueID }) else { return }
        change { project in
            for index in project.cues.indices where batch || project.cues[index].id == cueID {
                var patch = project.cues[index].styleOverrides[surtitleID] ?? TextStylePatch()
                patch.copy(property, from: style)
                project.cues[index].styleOverrides[surtitleID] = patch
            }
        }
    }
}
