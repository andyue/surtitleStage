import Foundation
import NDIBridge
import SubtitleCore

struct NDITarget: Equatable, Sendable {
    let outputID: UUID
    let name: String
    let canvas: CanvasDefinition
    let size: PixelSize
    let settings: NDISettings
    static func configured(in project: Project) throws -> [NDITarget] {
        var targets: [NDITarget] = []
        var pixels = 0
        for output in project.outputs where output.isEnabled && output.ndi.isEnabled {
            try output.ndi.validate()
            try output.validateMapping(canvases: project.canvases)
            guard let canvas = project.canvases.first(where: { $0.id == output.canvasID }) else { throw ProjectError.invalid("NDI output canvas is missing.") }
            let size = output.resolution ?? PixelSize(width: canvas.width, height: canvas.height)
            guard size.isValid, size.width <= 16384, size.height <= 16384, Int(size.width) % 2 == 0 else {
                throw ProjectError.invalid("NDI requires an even signal width and dimensions no greater than 16384 pixels. Set Output signal resolution explicitly; Canvas is unchanged.")
            }
            pixels += Int(size.width) * Int(size.height)
            guard pixels <= 16_777_216 else { throw ProjectError.invalid("NDI outputs exceed the combined 16 megapixel working budget. Reduce signal size or output count.") }
            let name = output.ndi.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            targets.append(NDITarget(outputID: output.id, name: name.isEmpty ? "SubtitleStage · " + (output.name.isEmpty ? output.id.uuidString : output.name) : name,
                                     canvas: canvas, size: size, settings: output.ndi))
        }
        guard !targets.isEmpty else { throw ProjectError.invalid("Enable NDI on at least one enabled output.") }
        guard Set(targets.map(\.name)).count == targets.count else { throw ProjectError.invalid("Use unique NDI source names for each output.") }
        return targets
    }
}

enum NDIRuntimeLocation {
    static let preferenceKey = "SubtitleStage.NDIRuntimePath"
    static var automatic: String? {
        // Runtime installation or the user's installed official NDI Tools; never copied into our app.
        ["/usr/local/lib/libndi.dylib", "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib",
         "/Applications/NDI Scan Converter.app/Contents/Frameworks/libndi.dylib",
         "/Applications/NDI Router.app/Contents/Frameworks/NTFramework.framework/Versions/A/Frameworks/libndi.dylib"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }
    static func resolve(_ selected: String) throws -> String {
        let path = selected.isEmpty ? automatic : selected
        guard let path, FileManager.default.fileExists(atPath: path) else {
            throw ProjectError.invalid("NDI runtime not found. Install the official NDI Runtime / Tools, or choose libndi.dylib in Video Output.")
        }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}

/// All mutable access is confined to the NDI manager's serial worker.
final class NDITransport: @unchecked Sendable {
    private struct Stream {
        let target: NDITarget
        let sender: UnsafeMutableRawPointer
        var cachedFrame: LiveFrame?
        var raster: Data?
        var pixels = Data()
        var cachedOpacity: Double?
        var lastPublished = -Double.infinity
    }
    private var runtime: OpaquePointer?
    private var streams: [Stream] = []
    private var envelope = VideoOpacityEnvelope()
    private var firstFrame = true
    private(set) var runtimeVersion = ""

    func start(_ targets: [NDITarget], runtimePath: String) throws {
        stop()
        var message = [CChar](repeating: 0, count: 2048)
        guard let runtime = ss_ndi_open(runtimePath, &message, message.count) else {
            throw ProjectError.invalid("NDI runtime unavailable: " + String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        self.runtime = runtime
        runtimeVersion = String(cString: ss_ndi_version(runtime))
        do {
            for target in targets {
                guard let sender = ss_ndi_sender_create(runtime, target.name) else { throw ProjectError.invalid("Cannot create NDI source: " + target.name) }
                streams.append(Stream(target: target, sender: sender))
            }
        } catch { stop(); throw error }
        envelope = VideoOpacityEnvelope(); firstFrame = true
    }
    func stop() {
        if let runtime { for stream in streams { ss_ndi_sender_destroy(runtime, stream.sender) } }
        streams = []; runtime = nil
    }
    func publish(frame: LiveFrame?, opacity: Double, duration: Double, time: Double) throws -> Int {
        guard let runtime else { return 0 }
        envelope.update(target: opacity, duration: firstFrame ? 0 : duration, at: time)
        firstFrame = false
        let value = envelope.value(at: time)
        var connections = 0
        for index in streams.indices {
            var stream = streams[index]
            connections += Int(ss_ndi_connections(runtime, stream.sender))
            guard time - stream.lastPublished >= 1 / Double(stream.target.settings.framesPerSecond) - 0.001 else { continue }
            if stream.raster == nil || stream.cachedFrame != frame {
                stream.raster = try VideoRasterizer.rgba(frame: frame, canvas: stream.target.canvas, outputID: stream.target.outputID, size: stream.target.size)
                stream.cachedFrame = frame; stream.cachedOpacity = nil
            }
            if stream.cachedOpacity != value {
                stream.pixels = Self.convert(stream.raster!, opacity: value, transparent: stream.target.settings.transparent)
                stream.cachedOpacity = value
            }
            let sender = stream.sender, target = stream.target
            stream.pixels.withUnsafeBytes { bytes in
                ss_ndi_send(runtime, sender, bytes.bindMemory(to: UInt8.self).baseAddress!,
                            Int32(target.size.width), Int32(target.size.height), Int32(target.settings.framesPerSecond))
            }
            stream.lastPublished = time; streams[index] = stream
        }
        return connections
    }
    static func convert(_ rgba: Data, opacity: Double, transparent: Bool) -> Data {
        precondition(rgba.count % 4 == 0)
        var result = Data(count: rgba.count)
        guard !rgba.isEmpty else { return result }
        result.withUnsafeMutableBytes { destination in
            rgba.withUnsafeBytes { source in
                ss_ndi_convert_rgba(source.bindMemory(to: UInt8.self).baseAddress!, destination.bindMemory(to: UInt8.self).baseAddress!,
                                    rgba.count / 4, min(1, max(0, opacity)), transparent)
            }
        }
        return result
    }
}
