import Foundation

public struct TextStyle: Codable, Equatable, Sendable {
    public var fontName = "PingFangTC-Regular"
    public var fontSize: Double = 72
    public var alignment: TextAlignment = .center
    public var characterSpacing: Double = 0
    public var lineSpacing: Double = 8
    public var color = TextColor()
    public var bold = false
    public var italic = false
    public var underline = false
    public var strikethrough = false
    public init() {}
}


public struct TextColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double = 1, green: Double = 1, blue: Double = 1, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public var isValid: Bool { [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
}

public enum TextProperty: String, CaseIterable, Sendable {
    case fontName, fontSize, characterSpacing, lineSpacing, color, bold, italic, underline, strikethrough, alignment
}

/// Field-level overrides ensure Batch changes only the chosen property.
public struct TextStylePatch: Codable, Equatable, Sendable {
    public var fontName: String?
    public var fontSize: Double?
    public var characterSpacing: Double?
    public var lineSpacing: Double?
    public var color: TextColor?
    public var bold: Bool?
    public var italic: Bool?
    public var underline: Bool?
    public var strikethrough: Bool?
    public var alignment: TextAlignment?
    public init() {}
    public mutating func copy(_ property: TextProperty, from style: TextStyle) {
        switch property {
        case .fontName: fontName = style.fontName
        case .fontSize: fontSize = style.fontSize
        case .characterSpacing: characterSpacing = style.characterSpacing
        case .lineSpacing: lineSpacing = style.lineSpacing
        case .color: color = style.color
        case .bold: bold = style.bold
        case .italic: italic = style.italic
        case .underline: underline = style.underline
        case .strikethrough: strikethrough = style.strikethrough
        case .alignment: alignment = style.alignment
        }
    }
    public func applying(to base: TextStyle) -> TextStyle {
        var style = base
        if let fontName { style.fontName = fontName }
        if let fontSize { style.fontSize = fontSize }
        if let characterSpacing { style.characterSpacing = characterSpacing }
        if let lineSpacing { style.lineSpacing = lineSpacing }
        if let color { style.color = color }
        if let bold { style.bold = bold }
        if let italic { style.italic = italic }
        if let underline { style.underline = underline }
        if let strikethrough { style.strikethrough = strikethrough }
        if let alignment { style.alignment = alignment }
        return style
    }
}

extension TextStyle {
    private enum CodingKeys: String, CodingKey { case fontName, fontSize, alignment, characterSpacing, lineSpacing, color, bold, italic, underline, strikethrough }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try c.decode(String.self, forKey: .fontName)
        fontSize = try c.decode(Double.self, forKey: .fontSize)
        alignment = try c.decode(TextAlignment.self, forKey: .alignment)
        characterSpacing = try c.decode(Double.self, forKey: .characterSpacing)
        lineSpacing = try c.decode(Double.self, forKey: .lineSpacing)
        color = try c.decodeIfPresent(TextColor.self, forKey: .color) ?? TextColor()
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try c.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        strikethrough = try c.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
    }
}
