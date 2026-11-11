import Foundation

public struct SyphonSettings: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var serverName = ""
    public var transparent = true
    public var framesPerSecond = 30
    public init() {}
    public func validate() throws {
        guard [30, 60].contains(framesPerSecond), serverName.count <= 128 else {
            throw ProjectError.invalid("Syphon requires 30 or 60 fps and a server name of at most 128 characters.")
        }
    }
}

/// A monotonic-time envelope shared by the transport worker and deterministic tests.
public struct VideoOpacityEnvelope: Sendable {
    private var start = 1.0
    private var target = 1.0
    private var began = 0.0
    private var duration = 0.0
    public init() {}
    public func value(at time: Double) -> Double {
        guard duration > 0 else { return target }
        let progress = min(1, max(0, (time - began) / duration))
        return start + (target - start) * progress
    }
    public mutating func update(target value: Double, duration: Double, at time: Double) {
        let value = min(1, max(0, value))
        guard value != target else { return }
        start = self.value(at: time); target = value; began = time; self.duration = max(0, duration)
    }
}
