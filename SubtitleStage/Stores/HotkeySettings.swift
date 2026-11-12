import AppKit
import SwiftUI
import SubtitleCore

@MainActor
final class HotkeySettings: ObservableObject {
    @Published private(set) var configuration: HotkeyConfiguration
    @Published var error: String?
    private let defaults: UserDefaults
    static let storageKey = "SubtitleStage.ShowControlHotkeys.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                let decoded = try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
                var validated = HotkeyConfiguration(bindings: [:])
                for (action, chord) in decoded.bindings { try validated.assign(chord, to: action) }
                configuration = validated
            } catch {
                configuration = HotkeyConfiguration(bindings: [:])
                self.error = "Saved hotkeys could not be loaded. Review assignments or restore defaults."
            }
        } else { configuration = HotkeyConfiguration() }
    }
    func assign(_ chord: HotkeyChord?, to action: PlaybackShortcut) {
        do {
            var next = configuration
            try next.assign(chord, to: action)
            try save(next)
        } catch { self.error = error.localizedDescription }
    }
    func restoreDefaults() {
        do { try save(HotkeyConfiguration()) } catch { self.error = error.localizedDescription }
    }
    private func save(_ value: HotkeyConfiguration) throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: Self.storageKey)
        configuration = value; error = nil
    }
    static func chord(for event: NSEvent) -> HotkeyChord? {
        guard !event.modifierFlags.contains(.command) else { return nil }
        var modifiers: UInt8 = 0
        if event.modifierFlags.contains(.shift) { modifiers |= 1 }
        if event.modifierFlags.contains(.control) { modifiers |= 2 }
        if event.modifierFlags.contains(.option) { modifiers |= 4 }
        let names: [UInt16: String] = [49: "Space", 36: "Return", 76: "Enter", 53: "Escape", 48: "Tab", 51: "Delete", 117: "Forward Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        let key = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        let prefix = (modifiers & 2 != 0 ? "⌃" : "") + (modifiers & 4 != 0 ? "⌥" : "") + (modifiers & 1 != 0 ? "⇧" : "")
        return HotkeyChord(keyCode: event.keyCode, modifiers: modifiers, label: prefix + key)
    }
}
