public enum PlaybackShortcut: Equatable, Sendable { case go, previous, toggleBlackout, blackout }
public enum ShortcutPolicy {
    public static func action(keyCode: UInt16, characters: String, isEditing: Bool, isOperatorWindow: Bool, hasModalUI: Bool, hasModifiers: Bool) -> PlaybackShortcut? {
        guard isOperatorWindow, !isEditing, !hasModalUI, !hasModifiers else { return nil }
        switch keyCode {
        case 49: return .go
        case 123: return .previous
        case 53: return .blackout
        default: return characters.lowercased() == "b" ? .toggleBlackout : nil
        }
    }
}
