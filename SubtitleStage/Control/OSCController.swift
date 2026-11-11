import Foundation
import Combine
import SubtitleCore

@MainActor
final class OSCController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Stopped"
    private var receiver: OSCReceiver?
    private var generation = UUID()

    func start(port: String, store: ProjectStore) {
        stop()
        guard let value = UInt16(port), value > 0 else {
            status = "Invalid UDP port. Enter 1–65535."; return
        }
        let token = generation
        do {
            receiver = try OSCReceiver(port: value) { [weak self, weak store] result in
                // Backpressure: do not accumulate an unbounded main-queue command backlog.
                DispatchQueue.main.sync {
                    guard let self, self.generation == token, self.isRunning, let store else { return }
                    switch result {
                    case .success(let commands):
                        guard !store.isBusy else { self.status = "Command ignored: project is busy."; return }
                        for command in commands {
                            if !store.performOSC(command) {
                                self.status = "Command ignored: cue UUID was not found."; return
                            }
                        }
                        self.status = "Listening on UDP \(value) · received \(commands.count) command(s)"
                    case .failure(let error):
                        if error is OSCDecoder.Invalid {
                            self.status = "OSC packet rejected: invalid or unsupported message."
                        } else {
                            self.stop()
                            self.status = "OSC receive failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
            isRunning = true
            status = "Listening on UDP \(value)"
        } catch { status = "Cannot listen on UDP \(value): \(error.localizedDescription)" }
    }
    func stop() {
        generation = UUID()
        receiver?.stop(); receiver = nil
        isRunning = false; status = "Stopped"
    }
}

extension ProjectStore {
    @discardableResult
    func performOSC(_ command: OSCCommand) -> Bool {
        guard !isBusy else { return false }
        switch command {
        case .go: go()
        case .previous: previous()
        case .toggleBlackout: toggleBlackout()
        case .blackout(let enabled):
            if playback.isBlackout != enabled { toggleBlackout() }
        case .cue(let id):
            guard project.cues.contains(where: { $0.id == id }) else { return false }
            let selection = playback.selectedCueID
            playback.selectedCueID = id
            showSelectedCue()
            playback.selectedCueID = selection
        }
        return true
    }
}
