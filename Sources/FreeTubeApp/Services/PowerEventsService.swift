import Foundation
import AppKit

/// Responds to system sleep/wake so playback politely pauses when the Mac
/// goes to sleep and can resume after waking (only if headphones are still
/// connected — the AirPods watcher handles the headphone case separately).
final class PowerEventsService: ObservableObject {
    static let shared = PowerEventsService()

    @Published var pauseOnSleep: Bool {
        didSet { UserDefaults.standard.set(pauseOnSleep, forKey: "power.pauseOnSleep") }
    }
    @Published var resumeOnWake: Bool {
        didSet { UserDefaults.standard.set(resumeOnWake, forKey: "power.resumeOnWake") }
    }
    @Published var lastEvent: String?

    private(set) var pausedForSleep = false
    private var configured = false

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "power.pauseOnSleep") == nil {
            defaults.set(true, forKey: "power.pauseOnSleep")
        }
        if defaults.object(forKey: "power.resumeOnWake") == nil {
            defaults.set(true, forKey: "power.resumeOnWake")
        }
        self.pauseOnSleep = defaults.bool(forKey: "power.pauseOnSleep")
        self.resumeOnWake = defaults.bool(forKey: "power.resumeOnWake")
    }

    /// Installs the workspace notification observers (idempotent).
    func activate() {
        guard !configured else { return }
        configured = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(handleWillSleep(_:)),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(handleDidWake(_:)),
                           name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func handleWillSleep(_ note: Notification) {
        guard pauseOnSleep else { return }
        let playing = isPlaying()
        if playing {
            _ = try? ShellHelper.runNamed("nowplaying-cli", arguments: ["pause"])
            pausedForSleep = true
            DispatchQueue.main.async {
                self.lastEvent = "Blocked playback before sleep"
            }
            setStateFile(true)
        }
    }

    @objc private func handleDidWake(_ note: Notification) {
        guard pausedForSleep else { return }
        pausedForSleep = false
        if resumeOnWake {
            _ = try? ShellHelper.runNamed("nowplaying-cli", arguments: ["play"])
            DispatchQueue.main.async {
                self.lastEvent = "Resumed playback after wake"
            }
        }
        setStateFile(false)
    }

    private func isPlaying() -> Bool {
        guard let rate = try? ShellHelper.runNamed("nowplaying-cli", arguments: ["get", "playbackRate"]) else {
            return false
        }
        let rateDouble = Double(rate) ?? 0
        return rateDouble > 0
    }

    private func setStateFile(_ paused: Bool) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeTube/.sleep-paused")
        try? "\(paused ? 1 : 0)".write(to: url, atomically: true, encoding: .utf8)
    }
}
