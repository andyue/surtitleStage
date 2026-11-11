import AppKit
import SubtitleCore

enum VideoRasterizer {
    static func rgba(frame: LiveFrame?, canvas: CanvasDefinition, outputID: UUID, size: PixelSize) throws -> Data {
        let width = Int(size.width), height = Int(size.height)
        guard size.isValid, width <= 16384, height <= 16384, width * height <= 33_554_432 else {
            throw ProjectError.invalid("Video image exceeds the supported texture or memory limit.")
        }
        var data = Data(count: width * height * 4)
        try data.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw ProjectError.invalid("Cannot allocate the video drawing surface.")
            }
            guard let frame else { return }
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            defer { NSGraphicsContext.restoreGraphicsState() }
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            CanvasContentRenderer.draw(frame, canvas: canvas, outputID: outputID, applyMapping: true,
                                       physicalOutput: false, previewResolution: size, bounds: bounds,
                                       backingBounds: bounds, contentOpacity: 1, context: context)
        }
        return data
    }
}
