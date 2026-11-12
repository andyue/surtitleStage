import XCTest
import AppKit
import Metal
import Syphon
@testable import SubtitleCore
@testable import SubtitleStage

final class SyphonTests: XCTestCase {
    private func project() -> Project {
        var project = Project()
        project.canvases[0].width = 320; project.canvases[0].height = 160
        project.languages[0].frame = PixelFrame(x: 10, y: 5, width: 300, height: 65)
        var cue = Cue(text: "字幕 ABC"); cue.style.fontSize = 30
        project.cues = [cue]
        var output = OutputConfiguration(name: "Test", canvasID: project.canvas.id)
        output.syphon.isEnabled = true
        project.outputs = [output]
        return project
    }
    func testEnvelopeContinuityAndBlackout() {
        var envelope = VideoOpacityEnvelope()
        envelope.update(target: 0, duration: 2, at: 10)
        XCTAssertEqual(envelope.value(at: 11), 0.5)
        envelope.update(target: 1, duration: 1, at: 11)
        XCTAssertEqual(envelope.value(at: 11), 0.5)
        XCTAssertEqual(envelope.value(at: 11.5), 0.75)
        XCTAssertEqual(envelope.value(at: 12), 1)
        envelope.update(target: 0, duration: 0, at: 12)
        XCTAssertEqual(envelope.value(at: 12), 0)
    }
    func testTargetResolutionAndLimitsDoNotRequireDisplay() throws {
        var project = project()
        var targets = try SyphonTarget.configured(in: project)
        XCTAssertEqual(targets[0].size, PixelSize(width: 320, height: 160))
        XCTAssertNil(project.outputs[0].displayID)
        project.outputs[0].resolution = PixelSize(width: 5760, height: 1080)
        targets = try SyphonTarget.configured(in: project)
        XCTAssertEqual(targets[0].size.width, 5760)
        project.outputs[0].resolution = PixelSize(width: 32768, height: 2)
        XCTAssertThrowsError(try SyphonTarget.configured(in: project))
        project.outputs[0].resolution = nil
        project.outputs[0].syphon.framesPerSecond = 0
        XCTAssertThrowsError(try project.validate())
    }
    func testVersionNineMigrationDefaultsAndRoundTrip() throws {
        let project = project()
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project)), project)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        json["projectFormatVersion"] = 9
        let migrated = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.projectFormatVersion, 12)
        XCTAssertFalse(migrated.outputs[0].syphon.isEnabled)
        XCTAssertEqual(migrated.cues, project.cues)
        XCTAssertEqual(migrated.outputs[0].id, project.outputs[0].id)
        try migrated.validate()
    }
    func testBackgroundRasterHasTransparentEdgesAndTopDownText() async throws {
        let project = project()
        let data = try await Task.detached {
            try VideoRasterizer.rgba(frame: LiveFrame(cue: project.cues[0], project: project),
                                      canvas: project.canvas, outputID: project.outputs[0].id, size: PixelSize(width: 320, height: 160))
        }.value
        XCTAssertEqual(data.count, 320 * 160 * 4)
        XCTAssertEqual(data[3], 0)
        let top = stride(from: 3, to: 320 * 80 * 4, by: 4).reduce(0) { $0 + Int(data[$1]) }
        let bottom = stride(from: 320 * 80 * 4 + 3, to: data.count, by: 4).reduce(0) { $0 + Int(data[$1]) }
        XCTAssertGreaterThan(top, 0)
        XCTAssertEqual(bottom, 0)
    }
    @MainActor func testPublishedOrientationPreservesHorizontalOrderAndConvertsVerticalOrigin() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Opt-in Metal/Syphon integration") }
        _ = NSApplication.shared
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        var project = project()
        // Asymmetric glyphs, left alignment, and an off-centre frame detect both axes.
        project.cues[0].text = "F 上 L 123"
        project.cues[0].style.alignment = .left
        project.languages[0].frame = PixelFrame(x: 17, y: 9, width: 240, height: 50)
        let frame = LiveFrame(cue: project.cues[0], project: project)
        let raster = try VideoRasterizer.rgba(frame: frame, canvas: project.canvas,
            outputID: project.outputs[0].id, size: PixelSize(width: 320, height: 160))
        let transport = SyphonTransport()
        try transport.start(SyphonTarget.configured(in: project))
        defer { transport.stop() }
        let client = SyphonMetalClient(serverDescription: try XCTUnwrap(transport.serverDescriptions.first),
            device: device, options: nil, newFrameHandler: nil)
        defer { client.stop() }
        try await Task.sleep(for: .milliseconds(100))
        try transport.publish(frame: frame, opacity: 1, duration: 0, time: 1)
        try await Task.sleep(for: .milliseconds(100))
        let texture = try XCTUnwrap(client.newFrameImage())
        var bytes = [UInt8](repeating: 0, count: raster.count)
        texture.getBytes(&bytes, bytesPerRow: 1280, from: MTLRegionMake2D(0, 0, 320, 160), mipmapLevel: 0)
        // Syphon's shared surface is consumed in bottom-left coordinates by GL clients.
        // Convert back to our top-left raster for comparison; x must stay unchanged.
        var mismatches = 0
        var occupied = 0
        for y in 0..<160 {
            for x in 0..<320 {
                let expected = Int(raster[(y * 320 + x) * 4 + 3])
                let actual = Int(bytes[((159 - y) * 320 + x) * 4 + 3])
                if abs(expected - actual) > 1 { mismatches += 1 }
                if expected > 0 { occupied += 1 }
            }
        }
        XCTAssertGreaterThan(occupied, 100)
        XCTAssertEqual(mismatches, 0, "Received glyphs must match the raster without horizontal mirroring or vertical inversion")
    }
    @MainActor func testRealMetalSyphonClientReceivesAlphaAndBlackout() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Opt-in Metal/Syphon integration") }
        _ = NSApplication.shared
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let project = project(), transport = SyphonTransport()
        try transport.start(SyphonTarget.configured(in: project))
        defer { transport.stop() }
        let description = try XCTUnwrap(transport.serverDescriptions.first)
        let client = SyphonMetalClient(serverDescription: description, device: device, options: nil, newFrameHandler: nil)
        defer { client.stop() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(client.isValid)
        let frame = LiveFrame(cue: project.cues[0], project: project)
        try transport.publish(frame: frame, opacity: 1, duration: 0, time: 1)
        try await Task.sleep(for: .milliseconds(100))
        let texture = try XCTUnwrap(client.newFrameImage())
        XCTAssertEqual(texture.width, 320); XCTAssertEqual(texture.height, 160)
        var bytes = [UInt8](repeating: 0, count: 320 * 160 * 4)
        texture.getBytes(&bytes, bytesPerRow: 320 * 4, from: MTLRegionMake2D(0, 0, 320, 160), mipmapLevel: 0)
        XCTAssertEqual(bytes[3], 0)
        XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 })
        try transport.publish(frame: frame, opacity: 0, duration: 0, time: 2)
        try await Task.sleep(for: .milliseconds(100))
        let black = try XCTUnwrap(client.newFrameImage())
        black.getBytes(&bytes, bytesPerRow: 320 * 4, from: MTLRegionMake2D(0, 0, 320, 160), mipmapLevel: 0)
        XCTAssertTrue(bytes.allSatisfy { $0 == 0 })
    }
}

extension SyphonTests {
    @MainActor func testMultipleServersFadeAndOpaqueBlackout() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Opt-in Metal/Syphon integration") }
        _ = NSApplication.shared
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        var project = project()
        var second = project.outputs[0]
        second.id = UUID(); second.name = "Opaque"; second.syphon.transparent = false
        project.outputs.append(second)
        let transport = SyphonTransport()
        try transport.start(SyphonTarget.configured(in: project))
        defer { transport.stop() }
        let clients = transport.serverDescriptions.map {
            SyphonMetalClient(serverDescription: $0, device: device, options: nil, newFrameHandler: nil)
        }
        defer { clients.forEach { $0.stop() } }
        try await Task.sleep(for: .milliseconds(100))
        let frame = LiveFrame(cue: project.cues[0], project: project)
        try transport.publish(frame: frame, opacity: 1, duration: 0, time: 1)
        try transport.publish(frame: frame, opacity: 0, duration: 2, time: 2)
        try transport.publish(frame: frame, opacity: 0, duration: 2, time: 3)
        try await Task.sleep(for: .milliseconds(100))
        let texture = try XCTUnwrap(clients[0].newFrameImage())
        var bytes = [UInt8](repeating: 0, count: 320 * 160 * 4)
        texture.getBytes(&bytes, bytesPerRow: 1280, from: MTLRegionMake2D(0, 0, 320, 160), mipmapLevel: 0)
        let maxAlpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }.max()!
        XCTAssertGreaterThan(maxAlpha, 100); XCTAssertLessThanOrEqual(maxAlpha, 128)
        try transport.publish(frame: frame, opacity: 0, duration: 2, time: 4)
        try await Task.sleep(for: .milliseconds(100))
        let black = try XCTUnwrap(clients[1].newFrameImage())
        black.getBytes(&bytes, bytesPerRow: 1280, from: MTLRegionMake2D(0, 0, 320, 160), mipmapLevel: 0)
        XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 })
        XCTAssertTrue(stride(from: 0, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 0 && bytes[$0+1] == 0 && bytes[$0+2] == 0 })
    }
    @MainActor func testManagerDoesNotTakeCueLiveAndStopsAfterConfigurationChange() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Opt-in Syphon lifecycle") }
        let store = ProjectStore()
        let project = project()
        store.change { $0 = project }
        store.playback.selectedCueID = project.cues[0].id
        let manager = SyphonOutputManager()
        defer { manager.stop() }
        manager.start(store: store)
        for _ in 0..<500 where manager.isStarting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(manager.activeOutputIDs, Set(project.outputs.map(\.id)))
        XCTAssertNil(store.playback.liveCueID)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(manager.configurationValidationCount, 1)
        store.setLanguageFrame(project.languages[0].id, frame: PixelFrame(x: -5, y: 10, width: 200, height: 60), outputID: project.outputs[0].id)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(manager.activeOutputIDs.isEmpty)
        XCTAssertEqual(manager.configurationValidationCount, 2)
        store.editOutputMapping(project.outputs[0].id) { $0.syphon.framesPerSecond = 60 }
        for _ in 0..<500 where !manager.activeOutputIDs.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(manager.activeOutputIDs.isEmpty)
        XCTAssertTrue(manager.status?.contains("settings changed") ?? false)
        XCTAssertNil(store.playback.liveCueID)
    }
}
