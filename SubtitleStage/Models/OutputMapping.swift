import Foundation

public enum ScaleMode: String, Codable, CaseIterable, Sendable {
    case fit, fill, stretch, pixel
    public var label: String {
        switch self { case .fit: "Fit"; case .fill: "Fill"; case .stretch: "Stretch"; case .pixel: "1:1 Pixel" }
    }
}

public struct PixelSize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public var isValid: Bool {
        [width, height].allSatisfy { $0.isFinite && (1...32768).contains($0) && $0.rounded() == $0 }
    }
    public var canvas: CanvasDefinition { CanvasDefinition(width: width, height: height) }
    public var frame: PixelFrame { PixelFrame(x: 0, y: 0, width: width, height: height) }
}

public struct OutputRegion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sourceCanvasID: UUID
    public var source: PixelFrame
    public var destination: PixelFrame
    public var scaleMode: ScaleMode
    public var isEnabled: Bool
    public init(id: UUID = UUID(), name: String, sourceCanvasID: UUID, source: PixelFrame,
                destination: PixelFrame, scaleMode: ScaleMode = .fit, isEnabled: Bool = true) {
        self.id = id; self.name = name; self.sourceCanvasID = sourceCanvasID
        self.source = source; self.destination = destination; self.scaleMode = scaleMode; self.isEnabled = isEnabled
    }
}

/// Source crop in canvas pixels -> destination in output-signal pixels.
/// Fit/Fill are centered; 1:1 anchors at the destination's top-left and clips.
public struct RegionTransform: Equatable, Sendable {
    public let scaleX: Double
    public let scaleY: Double
    public let offsetX: Double
    public let offsetY: Double
    public init?(source: PixelFrame, destination: PixelFrame, mode: ScaleMode) {
        guard source.hasValidGeometry, destination.hasValidGeometry else { return nil }
        let x = destination.width / source.width, y = destination.height / source.height
        switch mode {
        case .fit: scaleX = min(x, y); scaleY = min(x, y)
        case .fill: scaleX = max(x, y); scaleY = max(x, y)
        case .stretch: scaleX = x; scaleY = y
        case .pixel: scaleX = 1; scaleY = 1
        }
        offsetX = destination.x - source.x * scaleX + (mode == .pixel ? 0 : (destination.width - source.width * scaleX) / 2)
        offsetY = destination.y - source.y * scaleY + (mode == .pixel ? 0 : (destination.height - source.height * scaleY) / 2)
    }
    public func map(x: Double, y: Double) -> (x: Double, y: Double) { (x * scaleX + offsetX, y * scaleY + offsetY) }
}

extension PixelFrame {
    public var hasValidGeometry: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width >= 1 && height >= 1
    }
    public func fits(in size: PixelSize) -> Bool {
        hasValidGeometry && x + width <= size.width && y + height <= size.height
    }
    public func bounded(to size: PixelSize) -> PixelFrame {
        let w = min(size.width, max(1, width.rounded())), h = min(size.height, max(1, height.rounded()))
        return PixelFrame(x: min(max(0, x.rounded()), size.width - w), y: min(max(0, y.rounded()), size.height - h), width: w, height: h)
    }
}

public struct CanvasPreset: Identifiable, Sendable {
    public let width: Double
    public let height: Double
    public var id: String { "\(Int(width)) × \(Int(height))" }
    public static let all: [CanvasPreset] = [
        .init(width: 1920, height: 1080), .init(width: 1920, height: 1200),
        .init(width: 2560, height: 1440), .init(width: 3840, height: 1080),
        .init(width: 3840, height: 2160), .init(width: 4096, height: 2160),
        .init(width: 5760, height: 1080)
    ]
}

extension OutputConfiguration {
    public func validateMapping(canvases: [CanvasDefinition]) throws {
        guard resolution?.isValid ?? true else { throw ProjectError.invalid("Output resolution must be whole pixels between 1 and 32768.") }
        guard Set(regions.map(\.id)).count == regions.count else { throw ProjectError.invalid("Duplicate region UUIDs.") }
        guard regions.isEmpty || resolution != nil else { throw ProjectError.invalid("Set an explicit output resolution before adding regions.") }
        for region in regions {
            guard let canvas = canvases.first(where: { $0.id == region.sourceCanvasID }),
                  region.source.fits(in: PixelSize(width: canvas.width, height: canvas.height)),
                  let resolution, region.destination.fits(in: resolution),
                  [region.source.x, region.source.y, region.source.width, region.source.height,
                   region.destination.x, region.destination.y, region.destination.width, region.destination.height].allSatisfy({ $0.rounded() == $0 }) else {
                throw ProjectError.invalid("Region source or destination lies outside its pixel boundary.")
            }
        }
    }
}

extension OutputConfiguration {
    /// A configured signal must match the drawable backing pixels; never rescale it silently.
    public func validateDevice(backing: PixelSize, scanout: PixelSize) throws {
        guard backing.isValid, scanout.isValid else { throw ProjectError.invalid("Output display reports an invalid pixel size.") }
        if let resolution, resolution != backing {
            throw ProjectError.invalid("Output resolution does not match display backing pixels. Choose Use Display Pixels or change the macOS display mode.")
        }
        let usesPixel = regions.isEmpty ? scaleMode == .pixel : regions.contains { $0.isEnabled && $0.scaleMode == .pixel }
        if usesPixel && backing != scanout {
            throw ProjectError.invalid("1:1 Pixel requires an unscaled display mode. macOS backing pixels and physical display pixels differ.")
        }
    }
}
