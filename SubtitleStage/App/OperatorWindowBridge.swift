import AppKit
import SwiftUI
import SubtitleCore

struct OperatorWindowBridge: NSViewRepresentable {
    let store: ProjectStore
    let output: OutputManager
    let appDelegate: AppDelegate
    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.attach = { window in context.coordinator.attach(window) }
        return view
    }
    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {}
    static func dismantleNSView(_ nsView: WindowAttachmentView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.attach = nil
    }
    func makeCoordinator() -> Coordinator { Coordinator(store: store, output: output, appDelegate: appDelegate) }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        let store: ProjectStore
        let output: OutputManager
        let appDelegate: AppDelegate
        let controlsOnly: Bool
        var onClose: (() -> Void)?
        weak var window: NSWindow?
        private var monitor: Any?
        private var confirmingClose = false
        init(store: ProjectStore, output: OutputManager, appDelegate: AppDelegate, controlsOnly: Bool = false) {
            self.store = store; self.output = output; self.appDelegate = appDelegate; self.controlsOnly = controlsOnly
        }
        func attach(_ window: NSWindow) {
            self.window = window; window.delegate = self
            if !controlsOnly {
                output.operatorWindow = window
                appDelegate.store = store; appDelegate.output = output
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    if event.type != .keyDown {
                        self.updateFocus(after: event)
                        return false
                    }
                    return self.handle(event) == nil
                }
                return consumed ? nil : event
            }
        }
        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        func updateFocus(after event: NSEvent) {
            guard let window, event.window === window, window.attachedSheet == nil else { return }
            func marker(in view: NSView) -> ShowControlsFocusView? {
                if let result = view as? ShowControlsFocusView { return result }
                return view.subviews.lazy.compactMap { marker(in: $0) }.first
            }
            guard let content = window.contentView, let region = marker(in: content) else { return }
            let inside = region.bounds.contains(region.convert(event.locationInWindow, from: nil))
            // A click elsewhere disarms immediately, even when that view does not accept focus.
            if !inside, window.firstResponder is ShowControlsFocusView { window.makeFirstResponder(nil) }
            guard inside else { return }
            let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
            var ancestor = hit
            while let view = ancestor {
                if view is NSTextField || view is NSTextView { return }
                ancestor = view.superview
            }
            DispatchQueue.main.async { [weak window, weak region] in
                guard let window, let region, window.isKeyWindow, window.attachedSheet == nil,
                      NSApp.modalWindow == nil else { return }
                window.makeFirstResponder(region)
            }
        }
        func handle(_ event: NSEvent) -> NSEvent? {
            guard let window else { return event }
            let responder = window.firstResponder
            let editing = responder is NSText || responder is NSTextInputClient || responder is NSTextField
            let modifiers = !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            if !controlsOnly, !editing, !modifiers, event.window === window, window.isKeyWindow,
               window.attachedSheet == nil, NSApp.modalWindow == nil, store.layoutOutputID != nil, !(responder is ShowControlsFocusView) {
                let movement: (Double, Double)?
                switch event.keyCode {
                case 123: movement = (-1, 0)
                case 124: movement = (1, 0)
                case 125: movement = (0, 1)
                case 126: movement = (0, -1)
                default: movement = nil
                }
                if let movement {
                    store.nudgeSelectedLayout(dx: movement.0, dy: movement.1)
                    return nil
                }
            }
            guard let chord = HotkeySettings.chord(for: event),
                  ShortcutPolicy.action(chord: chord, configuration: store.hotkeys.configuration,
                    isEditing: editing, isOperatorWindow: event.window === window && window.isKeyWindow,
                    hasModalUI: window.attachedSheet != nil || output.operatorWindow?.attachedSheet != nil || NSApp.modalWindow != nil || store.isBusy,
                    isShowControlsFocused: responder is ShowControlsFocusView) != nil else { return event }
            // Consume auto-repeat without executing, including Return and Space.
            guard !event.isARepeat else { return nil }
            guard let action = ShortcutPolicy.action(chord: chord, configuration: store.hotkeys.configuration,
                    isEditing: editing, isOperatorWindow: true, hasModalUI: false,
                    isShowControlsFocused: true) else { return event }
            switch action {
            case .go: store.go()
            case .previous: store.previous()
            case .toggleBlackout: store.toggleBlackout()
            case .blackout: store.blackout()
            case .restore: if store.playback.isBlackout { store.toggleBlackout() }
            case .startOutput: output.startConfigured(store: store)
            case .stopOutput: output.stopAll()
            case .opacityUp: store.adjustMasterOpacity(by: 0.05)
            case .opacityDown: store.adjustMasterOpacity(by: -0.05)
            }
            return nil
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if controlsOnly { return true }
            guard !confirmingClose, !store.isBusy else { return false }
            confirmingClose = true
            Task {
                if await store.mayDiscard() {
                    output.stopAll()
                    sender.close()
                }
                confirmingClose = false
            }
            return false
        }
        func windowWillClose(_ notification: Notification) {
            if controlsOnly { detach(); onClose?() }
        }
        func windowDidResignKey(_ notification: Notification) { store.showControlsFocused = false }
        func windowDidBecomeKey(_ notification: Notification) {
            store.showControlsFocused = window?.firstResponder is ShowControlsFocusView
        }
        func windowDidChangeScreen(_ notification: Notification) { output.refresh() }
    }
}

final class WindowAttachmentView: NSView {
    var attach: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { attach?(window) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: ProjectStore?
    weak var output: OutputManager?
    private var awaitingTermination = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !awaitingTermination else { return .terminateCancel }
        guard let store else { return .terminateNow }
        guard !store.isBusy else { return .terminateCancel }
        awaitingTermination = true
        Task {
            let allowed = await store.mayDiscard()
            if allowed { output?.stopAll() }
            awaitingTermination = false
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }
}
