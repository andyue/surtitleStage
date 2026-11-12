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
        for (configuration, screen) in targets {
            let window = OutputWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.stopOutput = { [weak self] in self?.stopAll() }
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
        status = "\(windows.count) outputs running\(unassignedCount > 0 ? " · \(unassignedCount) unassigned" : "") · Double-click output to stop"
    }
    func stopAll() {
        let hadOutputs = !windows.isEmpty
        for window in windows.values { window.close() }
        windows.removeAll(); activeDisplayIDs.removeAll()
        status = nil
        if hadOutputs { operatorWindow?.makeKeyAndOrderFront(nil) }
        playbackStore = nil
    }
}

final class OutputWindow: NSWindow {
    var stopOutput: (() -> Void)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2 { stopOutput?(); return }
        super.sendEvent(event)
    }
    override func keyDown(with event: NSEvent) {
        // A dedicated escape route remains available when output covers the operator screen.
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty, !event.isARepeat { stopOutput?() }
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
