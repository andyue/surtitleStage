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
        weak var window: NSWindow?
        private var monitor: Any?
        private var confirmingClose = false
        init(store: ProjectStore, output: OutputManager, appDelegate: AppDelegate) {
            self.store = store; self.output = output; self.appDelegate = appDelegate
        }
        func attach(_ window: NSWindow) {
            self.window = window; window.delegate = self
            output.operatorWindow = window
            appDelegate.store = store; appDelegate.output = output
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.handle(event) == nil
                }
                return consumed ? nil : event
            }
        }
        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window else { return event }
            let responder = window.firstResponder
            let editing = responder is NSText || responder is NSTextInputClient || responder is NSTextField
            let modifiers = !event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            if !editing, !modifiers, event.window === window, window.isKeyWindow,
               window.attachedSheet == nil, NSApp.modalWindow == nil, store.layoutOutputID != nil {
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
            guard let action = ShortcutPolicy.action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "", isEditing: editing, isOperatorWindow: event.window === window && window.isKeyWindow, hasModalUI: window.attachedSheet != nil || NSApp.modalWindow != nil, hasModifiers: modifiers) else { return event }
            guard !event.isARepeat else { return nil }
            switch action {
            case .go: store.go()
            case .previous: store.previous()
            case .toggleBlackout: store.toggleBlackout()
            case .blackout:
                if !output.activeDisplayIDs.isEmpty { output.stopAll() }
                else { store.blackout() }
            }
            return nil
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
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
