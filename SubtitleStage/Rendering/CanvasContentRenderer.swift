import AppKit
import SubtitleCore

/// Shared pixel geometry and text drawing; callers own their CGContext and thread.
enum CanvasContentRenderer {
    static func draw(_ frameData: LiveFrame, canvas: CanvasDefinition, outputID: UUID?,
                     applyMapping: Bool, physicalOutput: Bool, previewResolution: PixelSize?,
                     bounds: CGRect, backingBounds: CGRect, contentOpacity: Double, context: CGContext) {
        let configuration = frameData.outputs.first { $0.id == outputID }
        let logical = applyMapping ? (configuration.flatMap { config in frameData.canvases.first { $0.id == config.canvasID } } ?? frameData.canvas) : canvas
        guard !applyMapping || configuration?.isEnabled != false else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(contentOpacity)
        if applyMapping, let configuration {
            let backing = backingBounds
            let signal = configuration.resolution ?? (!physicalOutput ? previewResolution : nil) ?? PixelSize(
                width: physicalOutput ? backing.width : logical.width,
                height: physicalOutput ? backing.height : logical.height)
            if physicalOutput {
                guard abs(signal.width - backing.width) < 0.5, abs(signal.height - backing.height) < 0.5 else { return }
                context.scaleBy(x: bounds.width / signal.width, y: bounds.height / signal.height)
            } else {
                guard let preview = CanvasTransform(canvas: signal.canvas, viewportWidth: bounds.width, viewportHeight: bounds.height) else { return }
                context.translateBy(x: preview.offsetX, y: preview.offsetY)
                context.scaleBy(x: preview.scale, y: preview.scale)
            }
            context.clip(to: CGRect(x: 0, y: 0, width: signal.width, height: signal.height))
            let regions = configuration.regions.isEmpty ? [OutputRegion(name: "Full canvas", sourceCanvasID: logical.id,
                source: PixelFrame(x: 0, y: 0, width: logical.width, height: logical.height),
                destination: signal.frame, scaleMode: configuration.scaleMode)] : configuration.regions
            for region in regions where region.isEnabled {
                guard frameData.canvases.contains(where: { $0.id == region.sourceCanvasID }),
                      let mapping = RegionTransform(source: region.source, destination: region.destination, mode: region.scaleMode) else { continue }
                context.saveGState()
                context.clip(to: CGRect(x: region.destination.x, y: region.destination.y, width: region.destination.width, height: region.destination.height))
                context.translateBy(x: mapping.offsetX, y: mapping.offsetY)
                context.scaleBy(x: mapping.scaleX, y: mapping.scaleY)
                context.clip(to: CGRect(x: region.source.x, y: region.source.y, width: region.source.width, height: region.source.height))
                drawLayers(frameData, outputID: outputID, context: context)
                context.restoreGState()
            }
        } else {
            guard let transform = CanvasTransform(canvas: logical, viewportWidth: bounds.width, viewportHeight: bounds.height) else { return }
            context.translateBy(x: transform.offsetX, y: transform.offsetY)
            context.scaleBy(x: transform.scale, y: transform.scale)
            context.clip(to: CGRect(x: 0, y: 0, width: logical.width, height: logical.height))
            drawLayers(frameData, outputID: outputID, context: context)
        }
    }
    private static func drawLayers(_ frameData: LiveFrame, outputID: UUID?, context: CGContext) {
        for language in frameData.layers(for: outputID) {
            drawText(frameData.text(for: language), style: frameData.style(for: language), frame: language.frame, rotation: language.rotation, context: context)
        }
    }
    private static func drawText(_ value: String, style: TextStyle, frame: PixelFrame, rotation: Rotation3D, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let x = rotation.x * .pi / 180
        let y = rotation.y * .pi / 180
        let z = rotation.z * .pi / 180
        let a = cos(z) * cos(y)
        let b = sin(z) * cos(y)
        let c = cos(z) * sin(x) * sin(y) - sin(z) * cos(x)
        let d = sin(z) * sin(x) * sin(y) + cos(z) * cos(x)
        let center = CGPoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
        context.translateBy(x: center.x, y: center.y)
        context.concatenate(CGAffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0))
        context.translateBy(x: -center.x, y: -center.y)
        context.clip(to: CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height))
        let text = attributedText(value, style: style)
        let measured = text.boundingRect(with: NSSize(width: frame.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        text.draw(with: NSRect(x: frame.x, y: frame.y + max(0, (frame.height - measured.height) / 2), width: frame.width, height: max(frame.height, measured.height)), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
    static func attributedText(_ value: String, style: TextStyle) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        switch style.alignment {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        paragraph.lineSpacing = max(0, style.lineSpacing)
        paragraph.lineBreakMode = .byWordWrapping
        let font = NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize)
        let boldFont = style.bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        let italicFont = style.italic ? NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask) : boldFont
        if style.lineSpacing < 0 {
            let natural = NSLayoutManager().defaultLineHeight(for: italicFont)
            let tightened = max(1, natural + style.lineSpacing)
            paragraph.minimumLineHeight = tightened
            paragraph.maximumLineHeight = tightened
        }
        let syntheticItalic = style.italic && !NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask)
        return NSAttributedString(string: value, attributes: [
            .font: italicFont,
            .obliqueness: syntheticItalic ? 0.2 : 0.0,
            .underlineStyle: style.underline ? NSUnderlineStyle.single.rawValue : 0,
            .strikethroughStyle: style.strikethrough ? NSUnderlineStyle.single.rawValue : 0,
            .foregroundColor: NSColor(srgbRed: style.color.red, green: style.color.green, blue: style.color.blue, alpha: style.color.alpha),
            .paragraphStyle: paragraph,
            .kern: style.characterSpacing
        ])
    }
    static func selectionFrame(text: String, style: TextStyle, frame: PixelFrame) -> PixelFrame {
        let measured = attributedText(text.isEmpty ? " " : text, style: style)
            .boundingRect(with: NSSize(width: frame.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = min(frame.height, max(1, ceil(measured.height)))
        return PixelFrame(x: frame.x, y: frame.y + (frame.height - height) / 2, width: frame.width, height: height)
    }

}
