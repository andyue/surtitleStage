import Foundation

public struct CanvasTransform: Equatable, Sendable {
    public let scale: Double
    public let offsetX: Double
    public let offsetY: Double
    public init?(canvas: CanvasDefinition, viewportWidth: Double, viewportHeight: Double) {
        guard canvas.width.isFinite, canvas.height.isFinite, canvas.width > 0, canvas.height > 0,
              viewportWidth.isFinite, viewportHeight.isFinite, viewportWidth > 0, viewportHeight > 0 else { return nil }
        scale = min(viewportWidth / canvas.width, viewportHeight / canvas.height)
        offsetX = (viewportWidth - canvas.width * scale) / 2
        offsetY = (viewportHeight - canvas.height * scale) / 2
    }
    public func toPreview(x: Double, y: Double) -> (x: Double, y: Double) { (x * scale + offsetX, y * scale + offsetY) }
    public func toCanvas(x: Double, y: Double) -> (x: Double, y: Double) { ((x - offsetX) / scale, (y - offsetY) / scale) }
}
