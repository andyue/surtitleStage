import Foundation
import SubtitleCore

extension ProjectStore {
    func canvas(for outputID: UUID?) -> CanvasDefinition {
        let id = project.outputs.first { $0.id == outputID }?.canvasID
        return project.canvases.first { $0.id == id } ?? project.canvas
    }

    func editOutputMapping(_ id: UUID, historyGroup: String? = nil, _ edit: (inout OutputConfiguration) -> Void) {
        guard let index = project.outputs.firstIndex(where: { $0.id == id }) else { return }
        var config = project.outputs[index]
        edit(&config)
        guard config != project.outputs[index] else { return }
        do {
            try config.validateMapping(canvases: project.canvases)
            try config.syphon.validate()
            try config.ndi.validate()
            change(historyGroup: historyGroup) { $0.outputs[index] = config }
        } catch { errorMessage = error.localizedDescription }
    }

    func setOutputResolution(_ id: UUID, size: PixelSize?) {
        guard size?.isValid ?? true else { errorMessage = "Output resolution must be whole pixels between 1 and 32768."; return }
        editOutputMapping(id) { $0.resolution = size }
    }

    @discardableResult
    func addRegion(to outputID: UUID, displaySize: PixelSize? = nil) -> UUID? {
        guard let config = project.outputs.first(where: { $0.id == outputID }) else { return nil }
        let sourceCanvas = canvas(for: outputID)
        let size = config.resolution ?? displaySize ?? PixelSize(width: sourceCanvas.width, height: sourceCanvas.height)
        let region = OutputRegion(name: "Region \(config.regions.count + 1)", sourceCanvasID: sourceCanvas.id,
                                  source: PixelFrame(x: 0, y: 0, width: sourceCanvas.width, height: sourceCanvas.height),
                                  destination: size.frame)
        editOutputMapping(outputID) { $0.resolution = size; $0.regions.append(region) }
        return region.id
    }

    func editRegion(_ id: UUID, outputID: UUID, historyGroup: String? = nil, _ edit: (inout OutputRegion) -> Void) {
        editOutputMapping(outputID, historyGroup: historyGroup) { config in
            guard let index = config.regions.firstIndex(where: { $0.id == id }) else { return }
            edit(&config.regions[index])
        }
    }

    func removeRegion(_ id: UUID, outputID: UUID) {
        editOutputMapping(outputID) { $0.regions.removeAll { $0.id == id } }
    }
}
