import XCTest
import Darwin
import SubtitleCore
@testable import SubtitleStage

final class OSCTests: XCTestCase {
    private func string(_ value: String) -> Data {
        var result = Data(value.utf8); result.append(0)
        while result.count % 4 != 0 { result.append(0) }
        return result
    }
    private func message(_ address: String, _ tags: String = ",", _ payload: Data = Data()) -> Data {
        string(address) + string(tags) + payload
    }
    private func word(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
    private func bundle(_ messages: [Data], time: UInt32 = 1) -> Data {
        messages.reduce(string("#bundle") + word(0) + word(time)) { $0 + word(UInt32($1.count)) + $1 }
    }
    func testCommandsAndExplicitBlackout() throws {
        let id = UUID()
        XCTAssertEqual(try OSCDecoder.decode(message("/subtitle/go")), [.go])
        XCTAssertEqual(try OSCDecoder.decode(message("/subtitle/previous")), [.previous])
        XCTAssertEqual(try OSCDecoder.decode(message("/subtitle/cue/\(id)")), [.cue(id)])
        XCTAssertEqual(try OSCDecoder.decode(message("/subtitle/blackout")), [.toggleBlackout])
        XCTAssertEqual(try OSCDecoder.decode(message("/subtitle/blackout", ",T")), [.blackout(true)])
        XCTAssertEqual(try OSCDecoder.decode(message("/subtitle/blackout", ",F")), [.blackout(false)])
        for value: UInt32 in [0, 1] {
            XCTAssertEqual(try OSCDecoder.decode(message("/subtitle/blackout", ",i", word(value))), [.blackout(value == 1)])
        }
        XCTAssertEqual(try OSCDecoder.decode(bundle([message("/subtitle/go"), bundle([message("/subtitle/previous")])])), [.go, .previous])
    }
    func testMalformedPacketsAreRejectedAsAWhole() {
        let valid = message("/subtitle/go")
        let invalid = [Data(), Data([47, 0, 1, 0]), valid + word(0), message("/subtitle/go", ",i", word(1)),
                       message("/subtitle/blackout", ",i", word(2)), message("/subtitle/cue/120"),
                       bundle([valid], time: 2), bundle([valid, message("/unknown")]),
                       string("#bundle") + word(0) + word(1) + word(UInt32.max)]
        for data in invalid { XCTAssertThrowsError(try OSCDecoder.decode(data)) }
        for length in 0..<valid.count { XCTAssertThrowsError(try OSCDecoder.decode(valid.prefix(length))) }
        var deep = valid
        for _ in 0..<10 { deep = bundle([deep]) }
        XCTAssertThrowsError(try OSCDecoder.decode(deep))
    }
    @MainActor
    func testRoutingPreservesSelectionAndBlackoutAndIdentity() async {
        let store = ProjectStore()
        store.addCue(); let first = store.selectedCue!.id
        store.addCue(); let second = store.selectedCue!.id
        XCTAssertTrue(store.performOSC(.cue(first)))
        XCTAssertEqual(store.playback.liveCueID, first)
        XCTAssertEqual(store.playback.selectedCueID, second)
        // One button sends the same no-argument OSC message twice.
        let toggle = try! OSCDecoder.decode(message("/subtitle/blackout"))[0]
        store.performOSC(toggle)
        XCTAssertTrue(store.playback.isBlackout)
        XCTAssertEqual(store.playback.liveCueID, first)
        store.performOSC(toggle)
        XCTAssertFalse(store.playback.isBlackout)
        XCTAssertEqual(store.playback.liveCueID, first)
        XCTAssertEqual(store.playback.selectedCueID, second)
        store.performOSC(.blackout(true)); store.performOSC(.blackout(true))
        XCTAssertTrue(store.playback.isBlackout)
        XCTAssertEqual(store.playback.liveCueID, first)
        store.performOSC(.blackout(false)); store.performOSC(.blackout(false))
        XCTAssertFalse(store.playback.isBlackout)
        store.performOSC(.go)
        XCTAssertEqual(store.playback.liveCueID, second)
        store.performOSC(.previous)
        XCTAssertEqual(store.playback.liveCueID, first)
        let playback = store.playback
        XCTAssertFalse(store.performOSC(.cue(UUID())))
        XCTAssertEqual(store.playback, playback)
    }
    func testUDPDeliveryAndPortConflict() async throws {
        let delivered = expectation(description: "UDP command decoded")
        let receiver = try OSCReceiver(port: 0) { result in
            if case .success(let commands) = result, commands == [.go] { delivered.fulfill() }
        }
        defer { receiver.stop() }
        XCTAssertThrowsError(try OSCReceiver(port: receiver.port) { _ in })
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = receiver.port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let data = message("/subtitle/go")
        let sent = data.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        XCTAssertEqual(sent, data.count)
        await fulfillment(of: [delivered], timeout: 3)
    }
}
