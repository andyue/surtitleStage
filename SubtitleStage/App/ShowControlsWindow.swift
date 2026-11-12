import AppKit
import SwiftUI

/// Owns presentation only. Both embedded and floating controls use the same store/output.
@MainActor
final class ShowControlsWindow: ObservableObject {
    @Published private(set) var isVisible = false
    private(set) var window: NSPanel?
    private var keyboard: OperatorWindowBridge.Coordinator?

    func show(store: ProjectStore, output: OutputManager) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 260),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Show Controls"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentMinSize = NSSize(width: 460, height: 240)
        panel.contentView = NSHostingView(rootView: ShowControlsView(store: store, output: output).padding(12))
        panel.center()
        panel.setFrameAutosaveName("SubtitleStage.ShowControls")
        let keyboard = OperatorWindowBridge.Coordinator(store: store, output: output, appDelegate: AppDelegate(), controlsOnly: true)
        keyboard.onClose = { [weak self, weak store] in
            store?.showControlsFocused = false
            self?.isVisible = false
            self?.window = nil
            self?.keyboard = nil
        }
        keyboard.attach(panel)
        self.keyboard = keyboard
        window = panel
        isVisible = true
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}
