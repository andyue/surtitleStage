import Foundation

public struct PixelFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public func adjusted(dx: Double, dy: Double, resizing: Bool, canvas: CanvasDefinition) -> PixelFrame {
        var frame = self
        if resizing {
            frame.width = min(32768, max(1, width + dx))
            frame.height = min(32768, max(1, height + dy))
        } else {
            frame.x = min(32768, max(-32768, x + dx))
            frame.y = min(32768, max(-32768, y + dy))
        }
        return frame
    }
}

public struct Rotation3D: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(x: Double = 0, y: Double = 0, z: Double = 0) {
        self.x = x; self.y = y; self.z = z
    }
}

public struct LanguageLayer: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var frame: PixelFrame
    public var style = TextStyle()
    public var rotation = Rotation3D()
    public var usesCueStyle = false
    public var isVisible = true
    // Empty means all outputs; nonempty is an explicit routing list.
    public var outputIDs: [UUID] = []
    public init(name: String, frame: PixelFrame, usesCueStyle: Bool = false) {
        self.name = name; self.frame = frame; self.usesCueStyle = usesCueStyle
    }
    public static func primary(canvas: CanvasDefinition) -> LanguageLayer {
        LanguageLayer(name: "Surtitle 1", frame: PixelFrame(x: canvas.width * 0.05, y: canvas.height * 0.65, width: canvas.width * 0.9, height: max(1, canvas.height * 0.2)), usesCueStyle: true)
    }
}

extension LanguageLayer {
    private enum CodingKeys: String, CodingKey { case id, name, frame, style, rotation, usesCueStyle, isVisible, outputIDs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        frame = try c.decode(PixelFrame.self, forKey: .frame)
        style = try c.decodeIfPresent(TextStyle.self, forKey: .style) ?? TextStyle()
        rotation = try c.decodeIfPresent(Rotation3D.self, forKey: .rotation) ?? Rotation3D()
        usesCueStyle = try c.decodeIfPresent(Bool.self, forKey: .usesCueStyle) ?? false
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        outputIDs = try c.decodeIfPresent([UUID].self, forKey: .outputIDs) ?? []
    }
}

/// A destination owns its layout; shared language IDs still identify cue text.
public struct LanguagePlacement: Codable, Equatable, Sendable {
    public var frame: PixelFrame
    public var style: TextStyle
    public var rotation: Rotation3D
    public var usesCueStyle: Bool
    public var isVisible: Bool
    public init(_ language: LanguageLayer) {
        frame = language.frame; style = language.style; rotation = language.rotation
        usesCueStyle = language.usesCueStyle; isVisible = language.isVisible
    }
    public func applying(to language: LanguageLayer) -> LanguageLayer {
        var result = language
        result.frame = frame; result.style = style; result.rotation = rotation
        result.usesCueStyle = usesCueStyle; result.isVisible = isVisible
        return result
    }
}

extension LanguagePlacement {
    private enum CodingKeys: String, CodingKey { case frame, style, rotation, usesCueStyle, isVisible }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frame = try c.decode(PixelFrame.self, forKey: .frame)
        style = try c.decode(TextStyle.self, forKey: .style)
        rotation = try c.decodeIfPresent(Rotation3D.self, forKey: .rotation) ?? Rotation3D()
        usesCueStyle = try c.decode(Bool.self, forKey: .usesCueStyle)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
    }
}
