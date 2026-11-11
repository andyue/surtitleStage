import Foundation
import Combine
import SubtitleCore

@MainActor
final class SyphonOutputManager: ObservableObject {
    @Published private(set) var activeOutputIDs: Set<UUID> = []
    @Published private(set) var isStarting = false
    @Published private(set) var status: String?
    private let queue = DispatchQueue(label: "SubtitleStage.Syphon", qos: .userInitiated)
    private let transport = SyphonTransport()
    private var timer: Timer?
    private var generation = 0
    private var inFlight = false
    private var targets: [SyphonTarget] = []
    private var sessionID: UUID?

    func start(store: ProjectStore) {
        guard !isStarting, activeOutputIDs.isEmpty, !store.isBusy else { return }
        let prepared: [SyphonTarget]
        do { prepared = try SyphonTarget.configured(in: store.project) }
        catch { status = error.localizedDescription; return }
        generation += 1
        let token = generation, session = store.sessionID, transport = transport
        isStarting = true; status = "Starting Syphon…"
        queue.async { [weak self] in
            do {
                try transport.start(prepared)
                Task { @MainActor [weak self, weak store] in
                    guard let self, self.generation == token else { return }
                    self.isStarting = false
                    guard let store, store.sessionID == session else { self.stop(); return }
                    self.targets = prepared; self.sessionID = session
                    self.activeOutputIDs = Set(prepared.map(\.outputID))
                    self.status = "Syphon running · " + prepared.map(\.name).joined(separator: ", ")
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
                    self.isStarting = false; self.status = "Syphon could not start: " + message
                }
            }
        }
    }
    func stop() {
        generation += 1
        timer?.invalidate(); timer = nil
        isStarting = false; activeOutputIDs = []; targets = []; sessionID = nil; inFlight = false
        status = "Syphon stopped."
        let transport = transport
        queue.async { transport.stop() }
    }
    private func tick(store: ProjectStore) {
        guard !activeOutputIDs.isEmpty, !inFlight else { return }
        guard store.sessionID == sessionID, (try? SyphonTarget.configured(in: store.project)) == targets else {
            stop(); status = "Syphon stopped after project or output settings changed. Review settings and start again."; return
        }
        inFlight = true
        let frame = store.playback.liveFrame, opacity = store.playback.visibleOpacity
        let duration = store.playback.transitionDuration, time = ProcessInfo.processInfo.systemUptime
        let token = generation, transport = transport
        queue.async { [weak self] in
            let errorMessage: String? = autoreleasepool {
                do { try transport.publish(frame: frame, opacity: opacity, duration: duration, time: time); return nil }
                catch { return error.localizedDescription }
            }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.inFlight = false
                if let errorMessage { self.stop(); self.status = "Syphon stopped: " + errorMessage }
            }
        }
    }
}
