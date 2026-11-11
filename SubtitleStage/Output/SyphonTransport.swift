import Foundation
import Metal
import Syphon
import SubtitleCore

struct SyphonTarget: Equatable, Sendable {
    let outputID: UUID
    let name: String
    let canvas: CanvasDefinition
    let size: PixelSize
    let settings: SyphonSettings

    static func configured(in project: Project) throws -> [SyphonTarget] {
        var targets: [SyphonTarget] = []
        var pixels = 0
        for output in project.outputs where output.isEnabled && output.syphon.isEnabled {
            try output.syphon.validate()
            try output.validateMapping(canvases: project.canvases)
            guard let canvas = project.canvases.first(where: { $0.id == output.canvasID }) else {
                throw ProjectError.invalid("Syphon output canvas is missing.")
            }
            let size = output.resolution ?? PixelSize(width: canvas.width, height: canvas.height)
            guard size.isValid, size.width <= 16384, size.height <= 16384 else {
                throw ProjectError.invalid("Syphon supports texture dimensions up to 16384 pixels.")
            }
            pixels += Int(size.width) * Int(size.height)
            guard pixels <= 33_554_432 else { throw ProjectError.invalid("Syphon outputs exceed the combined 512 MB working-surface budget. Reduce the output resolution or count.") }
            let custom = output.syphon.serverName.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = custom.isEmpty ? "SubtitleStage · " + (output.name.isEmpty ? output.id.uuidString : output.name) : custom
            targets.append(SyphonTarget(outputID: output.id, name: name, canvas: canvas, size: size, settings: output.syphon))
        }
        guard !targets.isEmpty else { throw ProjectError.invalid("Enable Syphon on at least one enabled output.") }
        guard Set(targets.map(\.name)).count == targets.count else { throw ProjectError.invalid("Use unique Syphon server names for each output.") }
        return targets
    }
}

/// All access is confined to SyphonOutputManager's serial worker queue.
final class SyphonTransport: @unchecked Sendable {
    private struct Stream {
        let target: SyphonTarget
        let server: SyphonMetalServer
        let input: any MTLTexture
        let output: any MTLTexture
        var cachedFrame: LiveFrame?
        var hasRaster = false
        var lastPublished = -Double.infinity
    }
    private var streams: [Stream] = []
    private var commandQueue: (any MTLCommandQueue)?
    private var pipeline: (any MTLComputePipelineState)?
    private var envelope = VideoOpacityEnvelope()
    private var firstFrame = true

    func start(_ targets: [SyphonTarget]) throws {
        stop()
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw ProjectError.invalid("Syphon requires a Metal-capable GPU.")
        }
        let library = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        kernel void opacityPass(texture2d<float, access::read> source [[texture(0)]],
                                texture2d<float, access::write> output [[texture(1)]],
                                constant float &opacity [[buffer(0)]],
                                constant uint &opaque [[buffer(1)]],
                                uint2 p [[thread_position_in_grid]]) {
            if (p.x >= output.get_width() || p.y >= output.get_height()) return;
            float4 value = source.read(p) * opacity;
            if (opaque != 0) value.a = 1.0;
            output.write(value, p);
        }
        """, options: nil)
        guard let function = library.makeFunction(name: "opacityPass") else { throw ProjectError.invalid("Cannot prepare the Syphon opacity shader.") }
        let preparedPipeline = try device.makeComputePipelineState(function: function)
        var prepared: [Stream] = []
        do {
            for target in targets {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                          width: Int(target.size.width), height: Int(target.size.height), mipmapped: false)
                descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .shaderWrite]
                guard let input = device.makeTexture(descriptor: descriptor),
                      let output = device.makeTexture(descriptor: descriptor) else {
                    throw ProjectError.invalid("Cannot create Syphon textures or server for " + target.name)
                }
                let candidate: SyphonMetalServer? = SyphonMetalServer(name: target.name, device: device, options: nil)
                guard let server = candidate else { throw ProjectError.invalid("Syphon server could not be created.") }
                prepared.append(Stream(target: target, server: server, input: input, output: output))
            }
        } catch {
            for stream in prepared { stream.server.stop() }
            throw error
        }
        commandQueue = queue; pipeline = preparedPipeline; streams = prepared
        envelope = VideoOpacityEnvelope(); firstFrame = true
    }
    func stop() {
        for stream in streams { stream.server.stop() }
        streams = []; commandQueue = nil; pipeline = nil
    }
    func publish(frame: LiveFrame?, opacity: Double, duration: Double, time: Double) throws {
        guard let queue = commandQueue, let pipeline else { return }
        envelope.update(target: opacity, duration: firstFrame ? 0 : duration, at: time)
        firstFrame = false
        for index in streams.indices {
            var stream = streams[index]
            guard time - stream.lastPublished >= 1 / Double(stream.target.settings.framesPerSecond) - 0.001 else { continue }
            if !stream.hasRaster || stream.cachedFrame != frame {
                let data = try VideoRasterizer.rgba(frame: frame, canvas: stream.target.canvas, outputID: stream.target.outputID, size: stream.target.size)
                data.withUnsafeBytes { bytes in
                    stream.input.replace(region: MTLRegionMake2D(0, 0, stream.input.width, stream.input.height),
                                         mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: stream.input.width * 4)
                }
                stream.cachedFrame = frame; stream.hasRaster = true
            }
            guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
                throw ProjectError.invalid("Metal could not prepare a Syphon frame.")
            }
            var opacity = Float(envelope.value(at: time))
            var opaque: UInt32 = stream.target.settings.transparent ? 0 : 1
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(stream.input, index: 0); encoder.setTexture(stream.output, index: 1)
            encoder.setBytes(&opacity, length: MemoryLayout<Float>.size, index: 0)
            encoder.setBytes(&opaque, length: MemoryLayout<UInt32>.size, index: 1)
            let width = pipeline.threadExecutionWidth
            let height = max(1, pipeline.maxTotalThreadsPerThreadgroup / width)
            encoder.dispatchThreads(MTLSize(width: stream.output.width, height: stream.output.height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
            encoder.endEncoding()
            // Our bitmap rows start at the top. Normalize once at the Syphon boundary
            // for bottom-left surface consumers (including QLab); preserve horizontal order.
            stream.server.publishFrameTexture(stream.output, on: command,
                                              imageRegion: NSRect(x: 0, y: 0, width: stream.output.width, height: stream.output.height), flipped: true)
            command.commit()
            command.waitUntilCompleted() // Worker queue only; prevents texture reuse before GPU completion.
            guard command.status == .completed else { throw ProjectError.invalid("Syphon GPU frame failed: " + (command.error?.localizedDescription ?? "unknown error")) }
            stream.lastPublished = time; streams[index] = stream
        }
    }

    // Used by the integration test to attach a real Syphon client.
    var serverDescriptions: [[String: Any]] { streams.map { $0.server.serverDescription } }
}
