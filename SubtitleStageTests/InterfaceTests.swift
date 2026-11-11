import XCTest
import SwiftUI
import AppKit
import SubtitleCore
@testable import SubtitleStage

final class InterfaceTests: XCTestCase {
    @MainActor
    func testNativeInterfaceSnapshots() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else {
            throw XCTSkip("Opt-in desktop rendering check: SUBTITLESTAGE_UI_CHECK=1 Scripts/test.sh --filter InterfaceTests")
        }
        _ = NSApplication.shared
        let store = ProjectStore()
        store.addCue()
        let first = store.selectedCue!.id
        let primary = store.project.languages[0].id
        let english = store.addLanguage()
        store.setText("好安靜的上海", cueID: first, languageID: primary)
        store.setText("Shanghai is so quiet.", cueID: first, languageID: english)
        store.setLanguageFrame(primary, frame: PixelFrame(x: 96, y: 390, width: 1728, height: 140))
        store.setLanguageFrame(english, frame: PixelFrame(x: 96, y: 570, width: 1728, height: 140))
        store.addCue()
        store.setText("我們在這裡等你。", cueID: store.selectedCue!.id, languageID: primary)
        store.setText("We are waiting for you here.", cueID: store.selectedCue!.id, languageID: english)
        store.playback.selectedCueID = first
        store.go()
        let output = OutputManager()
        store.addOutput(displayID: 101); store.addOutput(displayID: 102)
        let outputID = store.project.outputs[0].id
        _ = store.addRegion(to: outputID)
        let images: [(String, AnyView)] = [
            ("SubtitleStage-ndi-output.png", AnyView(ScrollView { NDISettingsView(store: store, ndi: NDIOutputManager()).padding() }.frame(width: 700, height: 980))),
            ("SubtitleStage-video-output.png", AnyView(ScrollView { VideoOutputView(store: store, syphon: SyphonOutputManager(), ndi: NDIOutputManager()).padding() }.frame(width: 700, height: 980))),
            ("SubtitleStage-mapping.png", AnyView(ScrollView { OutputMappingView(store: store, output: output, outputID: outputID).padding() }.frame(width: 700, height: 980))),
            ("SubtitleStage-table.png", AnyView(OperatorView(store: store, output: output, osc: OSCController()))),
            ("SubtitleStage-layout.png", AnyView(ScrollView { LayoutView(store: store, output: output).padding() }.frame(width: 700, height: 980))),
            ("SubtitleStage-layout-detail.png", AnyView(ScrollView { LayoutView(store: store, output: output, initialOutputID: store.project.outputs[0].id).padding() }.frame(width: 700, height: 980))),
            ("SubtitleStage-text-modify.png", AnyView(ScrollView { TextModifyView(store: store).padding() }.frame(width: 700, height: 980)))
        ]
        for (name, root) in images {
            let hosting = NSHostingView(rootView: root)
            let width: CGFloat = name.contains("table") ? 1150 : 700
            let height: CGFloat = name.contains("table") ? 850 : 980
            let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(500))
            hosting.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(name))
            XCTAssertGreaterThan(png.count, 10_000)
            window.close()
        }
    }
    @MainActor
    func testInteractionLatency() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Desktop benchmark") }
        _ = NSApplication.shared
        let store = ProjectStore()
        store.change { $0.cues = (1...200).map { Cue(displayNumber: String($0), text: "字幕 \($0)") } }
        store.addLanguage()
        store.playback.selectedCueID = store.project.cues[0].id
        let hosting = NSHostingView(rootView: OperatorView(store: store, output: OutputManager(), osc: OSCController()))
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 1150, height: 850), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting; window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        let start = Date()
        for cue in store.project.cues.prefix(20) {
            store.playback.selectedCueID = cue.id
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(1))
        }
        print("INTERACTION_BENCHMARK 200 cues, 20 selections: \(Date().timeIntervalSince(start)) seconds; installed fonts: \(NSFontManager.shared.availableFonts.count)")
    }

    @MainActor
    func testOwnScreenOutputAndEscape() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Desktop output test") }
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("The test runner has no NSScreen connection.") }
        let displayID = try XCTUnwrap(OutputManager.displayID(screen))
        let store = ProjectStore()
        store.addCue()
        store.setText("First", cueID: store.selectedCue!.id, languageID: store.project.languages[0].id)
        store.addCue()
        let selectedID = store.selectedCue!.id
        store.setText("Selected at start", cueID: selectedID, languageID: store.project.languages[0].id)
        XCTAssertNil(store.playback.liveCueID)
        store.addOutput(displayID: displayID)
        let manager = OutputManager()
        let operatorWindow = NSWindow(contentRect: NSRect(x: screen.frame.minX + 30, y: screen.frame.minY + 30, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        operatorWindow.isReleasedWhenClosed = false
        manager.operatorWindow = operatorWindow
        defer { manager.stopAll(); operatorWindow.close() }
        manager.startConfigured(store: store)
        XCTAssertEqual(store.playback.liveCueID, selectedID)
        XCTAssertFalse(store.playback.isBlackout)
        XCTAssertEqual(manager.activeDisplayIDs, [displayID])
        let outputWindow = try XCTUnwrap(NSApp.windows.first { $0 !== operatorWindow && $0.isVisible && $0.frame == screen.frame && $0.styleMask == .borderless })
        XCTAssertTrue(outputWindow.canBecomeKey)
        XCTAssertFalse(outputWindow.ignoresMouseEvents)
        XCTAssertGreaterThan(outputWindow.level.rawValue, NSWindow.Level.mainMenu.rawValue)
        let snapshot = store.playback.liveFrame
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: outputWindow.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        outputWindow.keyDown(with: escape)
        XCTAssertTrue(manager.activeDisplayIDs.isEmpty)
        XCTAssertFalse(outputWindow.isVisible)
        XCTAssertTrue(operatorWindow.isVisible)
        XCTAssertEqual(store.playback.liveFrame, snapshot)
        XCTAssertFalse(store.playback.isBlackout)
    }

    @MainActor
    func testNumberArrowKeysRespectIME() async throws {
        guard ProcessInfo.processInfo.environment["SUBTITLESTAGE_UI_CHECK"] == "1" else { throw XCTSkip("Desktop numeric editing") }
        _ = NSApplication.shared
        var value = 72.0
        let coordinator = NumericField.Coordinator(value: Binding(get: { value }, set: { value = $0 }), range: 1...2048)
        let editor = NSTextView(); let control = NSTextField()
        XCTAssertTrue(coordinator.control(control, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertEqual(value, 73)
        XCTAssertTrue(coordinator.control(control, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertEqual(value, 72)
        let fractional = NumericField.Coordinator(value: Binding(get: { value }, set: { value = $0 }), range: 0...100, step: 0.1)
        fractional.adjust(1, editor: nil)
        XCTAssertEqual(value, 72.1, accuracy: 0.0001)
        value = 72
        editor.setMarkedText("注音", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(coordinator.control(control, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertEqual(value, 72)
    }

}
