import AppKit
import XCTest
@testable import SubtitleStage
@testable import SubtitleCore

// XCTest runs outside a normal foreground app. Model key-window eligibility;
// actual activation/focus is checked separately in the packaged application.
private final class HotkeyTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

final class HotkeyFocusTests: XCTestCase {
    @MainActor
    func testFloatingControlsPreserveOutputOwnershipAndPlayback() throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Desktop panel lifecycle") }
        _ = NSApplication.shared
        let store = ProjectStore(), output = OutputManager()
        store.addCue(); store.go()
        let live = store.playback.liveCueID
        let main = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        output.operatorWindow = main
        let controller = ShowControlsWindow()
        controller.show(store: store, output: output)
        let panel = try XCTUnwrap(controller.window)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(output.operatorWindow === main)
        controller.show(store: store, output: output)
        XCTAssertTrue(controller.window === panel)
        controller.close()
        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(controller.window)
        XCTAssertEqual(store.playback.liveCueID, live)
        XCTAssertTrue(output.operatorWindow === main)
        main.close()
    }

    @MainActor
    func testFocusClickEditingAndRepeatGuards() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Desktop focus routing") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let store = ProjectStore(), output = OutputManager()
        // Preserve the operator's preferences: this test only uses the default if it is configured.
        guard store.hotkeys.configuration == HotkeyConfiguration() else { throw XCTSkip("User has customized hotkeys") }
        store.addCue(); let first = try XCTUnwrap(store.selectedCue?.id)
        store.addCue(); store.playback.selectedCueID = first
        let window = HotkeyTestWindow(contentRect: NSRect(x: 40, y: 40, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = try XCTUnwrap(window.contentView)
        let marker = ShowControlsFocusView(frame: NSRect(x: 0, y: 0, width: 250, height: 150))
        marker.changed = { store.showControlsFocused = $0 }
        content.addSubview(marker)
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 150, height: 24))
        content.addSubview(field)
        let coordinator = OperatorWindowBridge.Coordinator(store: store, output: output, appDelegate: AppDelegate(), controlsOnly: true)
        coordinator.attach(window)
        defer { coordinator.detach(); window.delegate = nil; window.close() }
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        func key(repeating: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeating, keyCode: 49))
        }
        func click(_ point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        window.makeFirstResponder(nil)
        XCTAssertNotNil(coordinator.handle(try key()))
        XCTAssertNil(store.playback.liveCueID)
        coordinator.updateFocus(after: try click(NSPoint(x: 200, y: 100)))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(window.firstResponder === marker)
        XCTAssertNil(coordinator.handle(try key()))
        XCTAssertEqual(store.playback.liveCueID, first)
        XCTAssertNil(coordinator.handle(try key(repeating: true)))
        XCTAssertEqual(store.playback.liveCueID, first)
        coordinator.updateFocus(after: try click(NSPoint(x: 400, y: 200)))
        XCTAssertFalse(window.firstResponder === marker)
        XCTAssertNotNil(coordinator.handle(try key()))
        window.makeFirstResponder(field)
        coordinator.updateFocus(after: try click(NSPoint(x: 40, y: 30)))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(window.firstResponder === marker)
        XCTAssertNotNil(coordinator.handle(try key()))
        XCTAssertEqual(store.playback.liveCueID, first)
    }
}
