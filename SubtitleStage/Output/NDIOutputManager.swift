import Foundation
import Combine
import SubtitleCore

@MainActor
final class NDIOutputManager: ObservableObject {
    @Published private(set) var activeOutputIDs: Set<UUID> = []
    @Published private(set) var isStarting = false
    @Published private(set) var status: String?
    @Published private(set) var connectionCount = 0
    private let queue = DispatchQueue(label: "SubtitleStage.NDI", qos: .userInitiated)
    private let transport = NDITransport()
    private var timer: Timer?
    private var generation = 0
    private var inFlight = false
    private var targets: [NDITarget] = []
    private var sessionID: UUID?
    private var validatedOutputs: [OutputConfiguration] = []
    private var validatedCanvases: [CanvasDefinition] = []
    private(set) var configurationValidationCount = 0

    func start(store: ProjectStore, runtimePath: String = "") {
        guard !isStarting, activeOutputIDs.isEmpty, !store.isBusy else { return }
        let prepared: [NDITarget]
        let resolvedPath: String
        do { prepared = try NDITarget.configured(in: store.project); resolvedPath = try NDIRuntimeLocation.resolve(runtimePath) }
        catch { status = error.localizedDescription; return }
        generation += 1
        validatedOutputs = []; validatedCanvases = []; configurationValidationCount = 0
        let token = generation, session = store.sessionID, transport = transport
        isStarting = true; status = "Starting NDI…"
        queue.async { [weak self] in
            do {
                try transport.start(prepared, runtimePath: resolvedPath)
                Task { @MainActor [weak self, weak store] in
                    guard let self, self.generation == token else { return }
                    self.isStarting = false
                    guard let store, store.sessionID == session else { self.stop(); return }
                    self.targets = prepared; self.sessionID = session
                    self.activeOutputIDs = Set(prepared.map(\.outputID))
                    self.status = "NDI running · " + prepared.map(\.name).joined(separator: ", ")
                    self.timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self, weak store] _ in
                        MainActor.assumeIsolated {
                            if let store { self?.tick(store: store) }
                        }
                    }
                    RunLoop.main.add(self.timer!, forMode: .common)
                    self.tick(store: store)
                }
            } catch {
                transport.stop()
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.isStarting = false; self.status = "NDI could not start: " + message
                }
            }
        }
    }
    func stop() {
        generation += 1
        timer?.invalidate(); timer = nil
        isStarting = false; activeOutputIDs = []; targets = []; sessionID = nil; inFlight = false
        connectionCount = 0; status = "NDI stopped. Receivers may retain the last frame."
        let transport = transport
        queue.async { transport.stop() }
    }
    func updateConnectionCount(_ value: Int) {
        if connectionCount != value { connectionCount = value }
    }
    private func configurationMatches(_ project: Project) -> Bool {
        guard project.outputs != validatedOutputs || project.canvases != validatedCanvases else { return true }
        configurationValidationCount += 1
        guard (try? NDITarget.configured(in: project)) == targets else { return false }
        validatedOutputs = project.outputs; validatedCanvases = project.canvases
        return true
    }
    private func tick(store: ProjectStore) {
        guard !activeOutputIDs.isEmpty, !inFlight else { return }
        guard store.sessionID == sessionID, configurationMatches(store.project) else {
            stop(); status = "NDI stopped after project or output settings changed. Review settings and start again."; return
        }
        inFlight = true
        let frame = store.playback.liveFrame, opacity = store.playback.visibleOpacity
        let duration = store.playback.transitionDuration, time = ProcessInfo.processInfo.systemUptime
        let token = generation, transport = transport
        queue.async { [weak self] in
            let result: (Int, String?) = autoreleasepool {
                do { return (try transport.publish(frame: frame, opacity: opacity, duration: duration, time: time), nil) }
                catch { return (0, error.localizedDescription) }
            }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.inFlight = false
                self.updateConnectionCount(result.0)
                if let errorMessage = result.1 { self.stop(); self.status = "NDI stopped: " + errorMessage }
            }
        }
    }
}
