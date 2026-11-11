import Foundation
import Darwin
import SubtitleCore

/// Socket reads and parsing run on one serial queue; only validated commands reach the UI.
final class OSCReceiver {
    private let source: DispatchSourceRead
    let port: UInt16

    init(port: UInt16, receive: @escaping @Sendable (Result<[OSCCommand], Error>) -> Void) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(fd); throw error
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        self.port = UInt16(bigEndian: address.sin_port)
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "SubtitleStage.OSC"))
        source.setEventHandler {
            // A bounded batch also keeps stop responsive under sustained traffic.
            for _ in 0..<32 {
                var buffer = [UInt8](repeating: 0, count: 65536)
                let count = recv(fd, &buffer, buffer.count, 0)
                if count < 0 {
                    if errno != EAGAIN && errno != EWOULDBLOCK {
                        receive(.failure(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)))
                    }
                    return
                }
                receive(Result { try OSCDecoder.decode(Data(buffer.prefix(count))) })
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }
    func stop() { source.cancel() }
    deinit { source.cancel() }
}
