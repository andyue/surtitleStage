import Foundation

public struct NDISettings: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var sourceName = ""
    public var transparent = true
    public var framesPerSecond = 30
    public init() {}
    public func validate() throws {
        guard [30, 60].contains(framesPerSecond), sourceName.utf8.count <= 128,
              !sourceName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ProjectError.invalid("NDI requires 30 or 60 fps and a source name of at most 128 UTF-8 bytes without control characters.")
        }
    }
}
