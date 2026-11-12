public enum PlaybackShortcut: String, Codable, CaseIterable, Sendable {
    case go, previous, toggleBlackout, blackout, restore, startOutput, stopOutput, opacityUp, opacityDown
    public var title: String {
        switch self {
        case .go: return "GO / Next"
        case .previous: return "Previous"
        case .toggleBlackout: return "Blackout / Restore"
        case .blackout: return "Blackout"
        case .restore: return "Restore"
        case .startOutput: return "Start Output"
        case .stopOutput: return "Stop Output"
        case .opacityUp: return "Opacity +5%"
        case .opacityDown: return "Opacity −5%"
        }
    }
}

public struct HotkeyChord: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    /// Shift = 1, Control = 2, Option = 4. Command is reserved for application menus.
    public var modifiers: UInt8
    public var label: String
    public init(keyCode: UInt16, modifiers: UInt8 = 0, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.label = label
    }
    public func matches(_ other: HotkeyChord) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
}

public struct HotkeyConfiguration: Codable, Equatable, Sendable {
    public var bindings: [PlaybackShortcut: HotkeyChord]
    public init(bindings: [PlaybackShortcut: HotkeyChord] = [.go: HotkeyChord(keyCode: 49, label: "Space"), .stopOutput: HotkeyChord(keyCode: 53, label: "Escape")]) {
        self.bindings = bindings
    }
    public mutating func assign(_ chord: HotkeyChord?, to action: PlaybackShortcut) throws {
        if let chord {
            guard chord.modifiers < 8 else { throw ProjectError.invalid("Command combinations are reserved for application menus.") }
            if let conflict = bindings.first(where: { $0.key != action && $0.value.matches(chord) }) {
                throw ProjectError.invalid("This key is already assigned to \(conflict.key.title). Clear that assignment first.")
            }
        }
        bindings[action] = chord
    }
}

public enum ShortcutPolicy {
    public static func action(chord: HotkeyChord, configuration: HotkeyConfiguration,
                              isEditing: Bool, isOperatorWindow: Bool, hasModalUI: Bool,
                              isShowControlsFocused: Bool, isRepeat: Bool = false) -> PlaybackShortcut? {
        guard isOperatorWindow, isShowControlsFocused, !isEditing, !hasModalUI, !isRepeat else { return nil }
        let matches = configuration.bindings.filter { $0.value.matches(chord) }
        // Corrupt or ambiguous preferences must never trigger an arbitrary playback action.
        guard matches.count == 1 else { return nil }
        return matches.first?.key
    }
}
