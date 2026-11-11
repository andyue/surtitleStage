import AppKit
import SwiftUI
import SubtitleCore

struct DisplayChoice: Identifiable {
    let id: UInt32
    let name: String
    let pixels: PixelSize
}

@MainActor
final class OutputManager: NSObject, ObservableObject {
    @Published private(set) var displays: [DisplayChoice] = []
    @Published private(set) var activeDisplayIDs: Set<UInt32> = []
    @Published var status: String?
    private var windows: [UInt32: NSWindow] = [:]
    private var keyboardMonitor: Any?
    private weak var playbackStore: ProjectStore?
    weak var operatorWindow: NSWindow?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refresh()
    }
    static func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    static func backingSize(_ screen: NSScreen) -> PixelSize {
        PixelSize(width: (screen.frame.width * screen.backingScaleFactor).rounded(), height: (screen.frame.height * screen.backingScaleFactor).rounded())
    }
    static func validate(_ config: OutputConfiguration, screen: NSScreen) throws {
        guard let id = displayID(screen) else { throw ProjectError.invalid("Output display has no identifier.") }
        try config.validateDevice(backing: backingSize(screen), scanout: PixelSize(width: Double(CGDisplayPixelsWide(id)), height: Double(CGDisplayPixelsHigh(id))))
    }
    @objc func refresh() {
        displays = NSScreen.screens.compactMap { screen in
            guard let id = Self.displayID(screen) else { return nil }
            return DisplayChoice(id: id, name: "\(screen.localizedName) · \(Int(screen.frame.width * screen.backingScaleFactor)) × \(Int(screen.frame.height * screen.backingScaleFactor))", pixels: Self.backingSize(screen))
        }
        for id in Array(windows.keys) {
            guard let screen = NSScreen.screens.first(where: { Self.displayID($0) == id }) else {
                stopAll()
                status = "Output display disconnected. Output stopped; select a display and start again."
                return
            }
            if let config = playbackStore?.project.outputs.first(where: { $0.displayID == id }) {
                do { try Self.validate(config, screen: screen) }
                catch { stopAll(); status = "Output stopped after display change. \(error.localizedDescription)"; return }
            }
            windows[id]?.setFrame(screen.frame, display: true)
        }
    }
    func startConfigured(store: ProjectStore) {
        let configurations = store.project.outputs.filter(\.isEnabled)
        guard !configurations.isEmpty else { status = "Add an output slot first."; return }
        let assigned = configurations.filter { $0.displayID != nil }
        guard !assigned.isEmpty else { status = "Assign a display device to at least one output in Layout Setting."; return }
        let operatorID = operatorWindow?.screen.flatMap(Self.displayID)
        var targets: [(OutputConfiguration, NSScreen)] = []
        for configuration in assigned {
            guard let displayID = configuration.displayID,
                  store.project.canvases.contains(where: { $0.id == configuration.canvasID }),
                  let screen = NSScreen.screens.first(where: { Self.displayID($0) == displayID }) else {
                status = "A destination or its canvas is unavailable. Update destinations in Layout Setting."
                return
            }
            do {
                try configuration.validateMapping(canvases: store.project.canvases)
                try Self.validate(configuration, screen: screen)
            } catch { status = error.localizedDescription; return }
            targets.append((configuration, screen))
        }
        store.showSelectedCue()
        stopAll()
        playbackStore = store
        installKeyboardMonitor()
        for (configuration, screen) in targets {
            let window = OutputWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.handleKey = { [weak self] event in self?.handleOutputKey(event) ?? false }
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.level = .init(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.hasShadow = false
            window.contentView = NSHostingView(rootView: OutputContent(store: store, outputID: configuration.id))
            window.setFrame(screen.frame, display: true)
            guard let displayID = configuration.displayID else { continue }
            windows[displayID] = window
            activeDisplayIDs.insert(displayID)
            window.orderFrontRegardless()
        }
        if let operatorID, let window = windows[operatorID] {
            operatorWindow?.makeFirstResponder(nil)
            window.makeKeyAndOrderFront(nil)
        }
        let unassignedCount = configurations.count - assigned.count
        status = "\(windows.count) outputs running\(unassignedCount > 0 ? " · \(unassignedCount) unassigned" : "") · Esc exits output"
    }
    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleOutputKey(event) ?? false }
            return consumed ? nil : event
        }
    }
    /// Only our output windows bypass editing guards; operator IME handling is unchanged.
    func handleOutputKey(_ event: NSEvent) -> Bool {
        guard let window = event.window, windows.values.contains(where: { $0 === window }),
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        if event.keyCode == 53 { stopAll(); return true }
        guard let action = ShortcutPolicy.action(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "", isEditing: false, isOperatorWindow: true, hasModalUI: false, hasModifiers: false) else { return false }
        guard !event.isARepeat else { return true }
        switch action {
        case .go: playbackStore?.go()
        case .previous: playbackStore?.previous()
        case .toggleBlackout: playbackStore?.toggleBlackout()
        case .blackout: break
        }
        return true
    }
    func stopAll() {
        let hadOutputs = !windows.isEmpty
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
        for window in windows.values { window.close() }
        windows.removeAll(); activeDisplayIDs.removeAll()
        status = nil
        if hadOutputs { operatorWindow?.makeKeyAndOrderFront(nil) }
        playbackStore = nil
    }
}

private final class OutputWindow: NSWindow {
    var handleKey: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if handleKey?(event) != true { super.keyDown(with: event) }
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private struct OutputContent: View {
    @ObservedObject var store: ProjectStore
    let outputID: UUID
    var body: some View {
        CanvasView(frame: store.playback.liveFrame, canvas: store.project.canvas, blackout: false, outputID: outputID, physicalOutput: true,
                   opacity: store.playback.visibleOpacity, transitionDuration: store.playback.transitionDuration)
            .ignoresSafeArea()
    }
}
