import XCTest
import AppKit
import NDITestSupport
@testable import SubtitleCore
@testable import SubtitleStage

final class NDITests: XCTestCase {
    private func project() -> Project {
        var p = Project()
        p.canvases[0].width = 320; p.canvases[0].height = 160
        p.languages[0].frame = PixelFrame(x: 12, y: 4, width: 200, height: 60)
        var cue = Cue(text: "F 上 L 123"); cue.style.fontSize = 28; cue.style.alignment = .left
        p.cues = [cue]
        var output = OutputConfiguration(name: "NDI-" + UUID().uuidString, canvasID: p.canvas.id)
        output.ndi.isEnabled = true; p.outputs = [output]
        return p
    }
    func testStraightAlphaFadeAndOpaquePixels() {
        let data = Data([64, 32, 16, 128, 99, 99, 99, 0, 255, 255, 255, 255])
        XCTAssertEqual(NDITransport.convert(data, opacity: 0.5, transparent: true), Data([128, 64, 32, 64, 0, 0, 0, 0, 255, 255, 255, 128]))
        XCTAssertEqual(NDITransport.convert(data, opacity: 0, transparent: true), Data(repeating: 0, count: 12))
        XCTAssertEqual(NDITransport.convert(Data([64, 32, 16, 128]), opacity: 0.5, transparent: false), Data([32, 16, 8, 255]))
        XCTAssertEqual(NDITransport.convert(Data([64, 32, 16, 128]), opacity: 0, transparent: false), Data([0, 0, 0, 255]))
    }
    func testTargetsUseSignalAndRejectOddWidthWithoutChangingCanvas() throws {
        var p = project(); p.canvases[0].width = 321
        XCTAssertThrowsError(try NDITarget.configured(in: p))
        p.outputs[0].resolution = PixelSize(width: 322, height: 160)
        XCTAssertEqual(try NDITarget.configured(in: p)[0].size.width, 322)
        XCTAssertEqual(p.canvas.width, 321)
        var other = p.outputs[0]; other.id = UUID(); p.outputs.append(other)
        XCTAssertThrowsError(try NDITarget.configured(in: p))
        p.outputs[1].ndi.sourceName = "Second"
        XCTAssertEqual(try NDITarget.configured(in: p).count, 2)
        p.outputs[0].ndi.framesPerSecond = 24
        XCTAssertThrowsError(try p.validate())
    }
    func testVersionTenMigrationAndRoundTrip() throws {
        let p = project()
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p)), p)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        json["projectFormatVersion"] = 10
        let migrated = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.projectFormatVersion, 12)
        XCTAssertFalse(migrated.outputs[0].ndi.isEnabled)
        XCTAssertEqual(migrated.cues, p.cues); XCTAssertEqual(migrated.outputs[0].id, p.outputs[0].id)
        XCTAssertEqual(migrated.outputs[0].syphon, p.outputs[0].syphon)
    }
    @MainActor func testMissingRuntimeLeavesPlaybackAndProjectUntouched() {
        let store = ProjectStore(); let p = project(); store.change { $0 = p }
        let manager = NDIOutputManager()
        manager.start(store: store, runtimePath: "/nonexistent/SubtitleStage/libndi.dylib")
        XCTAssertFalse(manager.isStarting); XCTAssertTrue(manager.activeOutputIDs.isEmpty)
        XCTAssertTrue(manager.status?.contains("runtime not found") ?? false)
        XCTAssertEqual(store.project, p); XCTAssertNil(store.playback.liveCueID)
    }
    @MainActor func testRealReceiverDiscoveryOrientationAlphaFadeBlackoutAndReconnect() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_NDI_CHECK"] == "1" else { throw XCTSkip("Opt-in NDI runtime/network integration") }
        _ = NSApplication.shared
        let path = try NDIRuntimeLocation.resolve("")
        let p = project(), transport = NDITransport()
        let targets = try NDITarget.configured(in: p)
        try transport.start(targets, runtimePath: path)
        defer { transport.stop() }
        var receiver: UnsafeMutableRawPointer? = try XCTUnwrap(ss_test_receiver_create(path, targets[0].name), "NDI source must be discoverable")
        defer { if let receiver { ss_test_receiver_destroy(receiver) } }
        let frame = LiveFrame(cue: p.cues[0], project: p)
        var time = 0.0
        func receive(opacity: Double, duration: Double = 0, matching: ([UInt8]) -> Bool) async throws -> [UInt8] {
            for _ in 0..<100 {
                time += 1.0 / 30
                _ = try transport.publish(frame: frame, opacity: opacity, duration: duration, time: time)
                var bytes = [UInt8](repeating: 0, count: 320 * 160 * 4)
                var w: Int32 = 0, h: Int32 = 0, fps: Int32 = 0
                let result = ss_test_receive(receiver, &bytes, bytes.count, &w, &h, &fps)
                if result == 1 {
                    XCTAssertEqual(w, 320); XCTAssertEqual(h, 160); XCTAssertEqual(fps, 30)
                    if matching(bytes) { return bytes }
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTFail("No matching NDI frame received"); return []
        }
        let full = try await receive(opacity: 1) { bytes in stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 240 } }
        func alpha(_ bytes: [UInt8], x: Range<Int>, y: Range<Int>) -> Int {
            y.reduce(0) { sum, row in sum + x.reduce(0) { $0 + Int(bytes[(row * 320 + $1) * 4 + 3]) } }
        }
        if !full.isEmpty {
            XCTAssertGreaterThan(alpha(full, x: 0..<220, y: 0..<80), 1000)
            XCTAssertLessThan(alpha(full, x: 0..<320, y: 100..<160), 100)
            XCTAssertLessThan(alpha(full, x: 250..<320, y: 0..<160), 100)
        }
        _ = try await receive(opacity: 0, duration: 1) { bytes in
            let peak = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }.max() ?? 0
            return peak > 90 && peak < 170
        }
        _ = try await receive(opacity: 0) { bytes in stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] < 3 } }
        ss_test_receiver_destroy(receiver)
        receiver = nil
        receiver = try XCTUnwrap(ss_test_receiver_create(path, targets[0].name))
        _ = try await receive(opacity: 1) { bytes in stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 240 } }
    }
}

extension NDITests {
    @MainActor func testManagerMultiOutputStartDoesNotGOAndSettingsStop() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_NDI_CHECK"] == "1" else { throw XCTSkip("Opt-in NDI lifecycle") }
        var p = project()
        var second = p.outputs[0]; second.id = UUID(); second.name += "-second"; second.ndi.transparent = false
        p.outputs.append(second)
        let store = ProjectStore(); store.change { $0 = p }
        store.playback.selectedCueID = p.cues[0].id
        let manager = NDIOutputManager(); defer { manager.stop() }
        manager.start(store: store)
        for _ in 0..<500 where manager.isStarting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(manager.activeOutputIDs, Set(p.outputs.map(\.id)))
        XCTAssertNil(store.playback.liveCueID)
        store.editOutputMapping(p.outputs[0].id) { $0.ndi.framesPerSecond = 60 }
        for _ in 0..<500 where !manager.activeOutputIDs.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(manager.activeOutputIDs.isEmpty)
        XCTAssertTrue(manager.status?.contains("settings changed") ?? false)
        XCTAssertNil(store.playback.liveCueID)
        store.undo(outputRunning: false)
        XCTAssertEqual(store.project.outputs[0].ndi.framesPerSecond, 30)
    }
    func testIncompatibleLibraryFailsWithoutCreatingSources() throws {
        let transport = NDITransport()
        defer { transport.stop() }
        XCTAssertThrowsError(try transport.start(NDITarget.configured(in: project()), runtimePath: "/usr/lib/libSystem.B.dylib"))
    }
}

extension NDITests {
    @MainActor func testTwoRealSourcesOpaqueBlackoutAndSixtyFPS() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_NDI_CHECK"] == "1" else { throw XCTSkip("Opt-in multiple NDI receivers") }
        let path = try NDIRuntimeLocation.resolve("")
        var p = project()
        var second = p.outputs[0]; second.id = UUID(); second.name += "-opaque"
        second.ndi.transparent = false; second.ndi.framesPerSecond = 60
        second.resolution = PixelSize(width: 640, height: 200); p.outputs.append(second)
        let targets = try NDITarget.configured(in: p), transport = NDITransport()
        try transport.start(targets, runtimePath: path); defer { transport.stop() }
        print("NDI_RUNTIME_VERIFIED " + transport.runtimeVersion)
        let first = try XCTUnwrap(ss_test_receiver_create(path, targets[0].name))
        defer { ss_test_receiver_destroy(first) }
        let secondReceiver = try XCTUnwrap(ss_test_receiver_create(path, targets[1].name))
        defer { ss_test_receiver_destroy(secondReceiver) }
        var received: Set<Int> = []
        let frame = LiveFrame(cue: p.cues[0], project: p)
        for iteration in 1...100 where received.count < 2 {
            _ = try transport.publish(frame: frame, opacity: 0, duration: 0, time: Double(iteration) / 30)
            for (index, receiver) in [first, secondReceiver].enumerated() where !received.contains(index) {
                var bytes = [UInt8](repeating: 9, count: 640 * 200 * 4)
                var w: Int32 = 0, h: Int32 = 0, fps: Int32 = 0
                if ss_test_receive(receiver, &bytes, bytes.count, &w, &h, &fps) == 1 {
                    XCTAssertEqual(w, index == 0 ? 320 : 640); XCTAssertEqual(h, index == 0 ? 160 : 200)
                    XCTAssertEqual(fps, index == 0 ? 30 : 60)
                    let count = Int(w * h * 4)
                    XCTAssertTrue(stride(from: 3, to: count, by: 4).allSatisfy { index == 0 ? bytes[$0] < 3 : bytes[$0] == 255 })
                    XCTAssertTrue(stride(from: 0, to: count, by: 4).allSatisfy { bytes[$0] < 5 && bytes[$0+1] < 5 && bytes[$0+2] < 5 })
                    received.insert(index)
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(received.count, 2)
    }
}
