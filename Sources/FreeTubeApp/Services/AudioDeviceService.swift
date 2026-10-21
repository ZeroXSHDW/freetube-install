import Foundation
import CoreAudio

enum AudioDeviceError: Error, LocalizedError {
    case helperNotFound
    case deviceQueryFailed

    var errorDescription: String? {
        switch self {
        case .helperNotFound:
            return "audiodevice helper not found"
        case .deviceQueryFailed:
            return "Failed to query audio device"
        }
    }
}

struct AudioDeviceInfo {
    let name: String
    var isHeadphones: Bool {
        name.range(of: #"(AirPods|Beats|Headphone|Headset|Buds|JBL|Sony|Bose|Sennheiser|Soundcore|Bluetooth|WH|WF|QuietComfort|Momentum)"#, options: .regularExpression) != nil
    }
    var isBuiltin: Bool {
        name.range(of: #"(MacBook|Speaker|Internal|Built-?in|Built In|Internal Speakers)"#, options: .regularExpression) != nil
    }
}

final class AudioDeviceService: ObservableObject {
    static let shared = AudioDeviceService()

    @Published var currentDevice: AudioDeviceInfo?
    @Published var isMonitoring = false
    @Published var wasPlayingWhenPaused: Bool = false
    @Published var lastEvent: String?

    private var monitoringTask: Task<Void, Never>?
    private let audiodevicePath: URL
    private let nowPlayingCLI: String
    private let checkInterval: Double = 3.0
    private let logQueue = DispatchQueue(label: "com.freetube.audiopause.log", qos: .utility)

    private var previousDeviceName: String?

    init() {
        self.audiodevicePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeTubeBar/audiodevice")
        self.nowPlayingCLI = Self.findNowPlayingCLI()
    }

    private static func findNowPlayingCLI() -> String {
        for candidate in ["/opt/homebrew/bin/nowplaying-cli", "/usr/local/bin/nowplaying-cli",
                          "/opt/local/bin/nowplaying-cli"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "nowplaying-cli"
    }

    func getCurrentDevice() -> AudioDeviceInfo? {
        guard let output = try? ShellHelper.run(audiodevicePath.path, arguments: []) else {
            return nil
        }
        return AudioDeviceInfo(name: output)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        previousDeviceName = getCurrentDevice()?.name

        monitoringTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
                checkDeviceChange()
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        isMonitoring = false
    }

    private func checkDeviceChange() {
        guard let current = getCurrentDevice() else { return }
        let currentName = current.name

        guard let previous = previousDeviceName, previous != currentName else {
            previousDeviceName = currentName
            return
        }

        let prevDevice = AudioDeviceInfo(name: previous)

        // Headphones removed -> built-in
        if prevDevice.isHeadphones && current.isBuiltin {
            if isFreeTubePlaying() {
                log("Headphones removed (\(previous) -> \(currentName)); pausing FreeTube.")
                pauseFreeTube()
                wasPlayingWhenPaused = true
                savePauseState(true)
            }
        }
        // Headphones connected
        else if prevDevice.isBuiltin && current.isHeadphones {
            if wasPlayingWhenPaused {
                log("Headphones reconnected (\(previous) -> \(currentName)); resuming FreeTube.")
                resumeFreeTube()
                wasPlayingWhenPaused = false
                savePauseState(false)
            }
        }

        previousDeviceName = currentName

        Task { @MainActor in
            self.currentDevice = current
            self.lastEvent = "\(previous) -> \(currentName)"
        }
    }

    private func isFreeTubePlaying() -> Bool {
        let rate = try? ShellHelper.run(nowPlayingCLI, arguments: ["get", "playbackRate"])
        guard rate == "1" else { return false }
        let raw = try? ShellHelper.run(nowPlayingCLI, arguments: ["get-raw"])
        return raw?.contains("io.freetubeapp.freetube") ?? false
    }

    private func pauseFreeTube() {
        _ = try? ShellHelper.run(nowPlayingCLI, arguments: ["pause"])
    }

    private func resumeFreeTube() {
        _ = try? ShellHelper.run(nowPlayingCLI, arguments: ["play"])
    }

    private func savePauseState(_ paused: Bool) {
        let stateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeTube/.audiopause-state")
        try? "\(paused ? 1 : 0)".write(to: stateURL, atomically: true, encoding: .utf8)
    }

    private func log(_ message: String) {
        logQueue.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let line = "[\(timestamp)] \(message)"
            if let logURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/FreeTubeAirPods.log") as URL? {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write((line + "\n").data(using: .utf8) ?? Data())
                    handle.closeFile()
                }
            }
            DispatchQueue.main.async {
                self.lastEvent = message
            }
        }
    }
}
