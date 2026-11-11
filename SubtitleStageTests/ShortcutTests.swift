import XCTest
@testable import SubtitleCore

final class ShortcutTests: XCTestCase {
    func testEditingAndModalUINeverConsumePlaybackKeys() {
        for key: UInt16 in [49, 123, 53, 11, 36, 124, 125, 126] {
            XCTAssertNil(ShortcutPolicy.action(keyCode: key, characters: "b", isEditing: true, isOperatorWindow: true, hasModalUI: false, hasModifiers: false))
            XCTAssertNil(ShortcutPolicy.action(keyCode: key, characters: "b", isEditing: false, isOperatorWindow: true, hasModalUI: true, hasModifiers: false))
            XCTAssertNil(ShortcutPolicy.action(keyCode: key, characters: "b", isEditing: false, isOperatorWindow: false, hasModalUI: false, hasModifiers: false))
            XCTAssertNil(ShortcutPolicy.action(keyCode: key, characters: "b", isEditing: false, isOperatorWindow: true, hasModalUI: false, hasModifiers: true))
        }
    }
    func testPlaybackKeys() {
        for (key, text, expected): (UInt16, String, PlaybackShortcut) in [(49, " ", .go), (123, "", .previous), (53, "", .blackout), (11, "b", .toggleBlackout)] {
            XCTAssertEqual(ShortcutPolicy.action(keyCode: key, characters: text, isEditing: false, isOperatorWindow: true, hasModalUI: false, hasModifiers: false), expected)
        }
        XCTAssertNil(ShortcutPolicy.action(keyCode: 36, characters: "\r", isEditing: false, isOperatorWindow: true, hasModalUI: false, hasModifiers: false))
    }
}
