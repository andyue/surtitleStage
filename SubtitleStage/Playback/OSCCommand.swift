import Foundation

public enum OSCCommand: Equatable, Sendable {
    case go, previous, toggleBlackout, blackout(Bool), cue(UUID)
}

/// Strict, bounded OSC subset. Validate the entire datagram before executing anything.
public enum OSCDecoder {
    public enum Invalid: Error { case packet }
    public static func decode(_ data: Data) throws -> [OSCCommand] {
        guard !data.isEmpty, data.count <= 65507 else { throw Invalid.packet }
        var budget = 128
        return try packet(Array(data), depth: 0, budget: &budget)
    }
    private static func packet(_ bytes: [UInt8], depth: Int, budget: inout Int) throws -> [OSCCommand] {
        guard depth < 8, bytes.count % 4 == 0, budget > 0 else { throw Invalid.packet }
        budget -= 1
        var offset = 0
        func string() throws -> String {
            guard offset < bytes.count, let end = bytes[offset...].firstIndex(of: 0) else { throw Invalid.packet }
            let next = (end + 4) & ~3
            guard next <= bytes.count, bytes[end..<next].allSatisfy({ $0 == 0 }),
                  let value = String(bytes: bytes[offset..<end], encoding: .utf8) else { throw Invalid.packet }
            offset = next
            return value
        }
        func word() throws -> UInt32 {
            guard offset + 4 <= bytes.count else { throw Invalid.packet }
            defer { offset += 4 }
            return bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | UInt32($1) }
        }
        let address = try string()
        if address == "#bundle" {
            // Only explicit immediate bundles: never execute a scheduled cue early.
            guard try word() == 0, try word() == 1 else { throw Invalid.packet }
            var commands: [OSCCommand] = []
            while offset < bytes.count {
                let size = Int(try word())
                guard size > 0, size <= bytes.count - offset else { throw Invalid.packet }
                commands += try packet(Array(bytes[offset..<offset + size]), depth: depth + 1, budget: &budget)
                offset += size
            }
            return commands
        }
        let tags = try string()
        let command: OSCCommand
        switch address {
        case "/subtitle/go", "/subtitle/previous":
            guard tags == "," else { throw Invalid.packet }
            command = address == "/subtitle/go" ? .go : .previous
        case "/subtitle/blackout":
            switch tags {
            case ",": command = .toggleBlackout
            case ",T": command = .blackout(true)
            case ",F": command = .blackout(false)
            case ",i":
                let value = try word()
                guard value <= 1 else { throw Invalid.packet }
                command = .blackout(value == 1)
            default: throw Invalid.packet
            }
        default:
            let prefix = "/subtitle/cue/"
            guard tags == ",", address.hasPrefix(prefix),
                  let id = UUID(uuidString: String(address.dropFirst(prefix.count))) else { throw Invalid.packet }
            command = .cue(id)
        }
        guard offset == bytes.count else { throw Invalid.packet }
        return [command]
    }
}
