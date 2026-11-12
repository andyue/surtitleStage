import XCTest
@testable import SubtitleCore
@testable import SubtitleStage

final class ShortcutTests: XCTestCase {
    private let space = HotkeyChord(keyCode: 49, label: "Space")
    func testSpaceAndEscapeInFocusedShowControlsByDefault() {
        let config = HotkeyConfiguration()
        XCTAssertEqual(config.bindings.count, 2)
        XCTAssertEqual(ShortcutPolicy.action(chord: space, configuration: config, isEditing: false, isOperatorWindow: true, hasModalUI: false, isShowControlsFocused: true), .go)
        for key: UInt16 in [123, 11, 36, 124, 125, 126] {
            XCTAssertNil(ShortcutPolicy.action(chord: HotkeyChord(keyCode: key, label: "test"), configuration: config, isEditing: false, isOperatorWindow: true, hasModalUI: false, isShowControlsFocused: true))
        }
        for (editing, operatorWindow, modal, focus, repeating) in [(true,true,false,true,false), (false,false,false,true,false), (false,true,true,true,false), (false,true,false,false,false), (false,true,false,true,true)] {
            XCTAssertNil(ShortcutPolicy.action(chord: space, configuration: config, isEditing: editing, isOperatorWindow: operatorWindow, hasModalUI: modal, isShowControlsFocused: focus, isRepeat: repeating))
        }
    }
    func testAssignmentModifiersConflictsClearAndRoundTrip() throws {
        var config = HotkeyConfiguration()
        XCTAssertThrowsError(try config.assign(HotkeyChord(keyCode: 49, label: "Different label"), to: .previous))
        let shifted = HotkeyChord(keyCode: 49, modifiers: 1, label: "⇧Space")
        try config.assign(shifted, to: .previous)
        XCTAssertEqual(ShortcutPolicy.action(chord: shifted, configuration: config, isEditing: false, isOperatorWindow: true, hasModalUI: false, isShowControlsFocused: true), .previous)
        try config.assign(nil, to: .go)
        XCTAssertNil(config.bindings[.go])
        XCTAssertEqual(try JSONDecoder().decode(HotkeyConfiguration.self, from: JSONEncoder().encode(config)), config)
        XCTAssertThrowsError(try config.assign(HotkeyChord(keyCode: 1, modifiers: 8, label: "invalid"), to: .go))
        let ambiguous = HotkeyConfiguration(bindings: [.go: space, .previous: space])
        XCTAssertNil(ShortcutPolicy.action(chord: space, configuration: ambiguous, isEditing: false, isOperatorWindow: true, hasModalUI: false, isShowControlsFocused: true))
    }
    @MainActor
    func testPreferencesPersistAndInvalidPreferencesFailClosed() throws {
        let suite = "SubtitleStageTests.Hotkeys." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HotkeySettings(defaults: defaults)
        settings.assign(nil, to: .go)
        settings.assign(HotkeyChord(keyCode: 11, label: "B"), to: .blackout)
        XCTAssertEqual(HotkeySettings(defaults: defaults).configuration, settings.configuration)
        settings.restoreDefaults()
        XCTAssertEqual(settings.configuration, HotkeyConfiguration())
        defaults.set(Data("broken".utf8), forKey: HotkeySettings.storageKey)
        let broken = HotkeySettings(defaults: defaults)
        XCTAssertTrue(broken.configuration.bindings.isEmpty)
        XCTAssertNotNil(broken.error)
    }
}
