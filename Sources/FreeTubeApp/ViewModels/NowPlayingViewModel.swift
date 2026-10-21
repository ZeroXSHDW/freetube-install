import Foundation
import SwiftUI

@MainActor
final class NowPlayingViewModel: ObservableObject {
    @Published var title: String = "Nothing playing"
    @Published var artist: String = "Pick a genre from the ♫ menu"
    @Published var currentTime: String = "0:00"
    @Published var duration: String = "0:00"
    @Published var progress: Double = 0
    @Published var isPlaying: Bool = false
    @Published var artwork: NSImage?
    @Published var isFavorite: Bool = false
    @Published var isWatchLater: Bool = false

    private var timer: Timer?

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let output = try? ShellHelper.run("nowplaying-cli", arguments: ["get-raw"])
        guard let data = output?.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            title = "Nothing playing"
            artist = "Pick a genre from the ♫ menu"
            progress = 0
            currentTime = "0:00"
            duration = "0:00"
            isPlaying = false
            return
        }

        title = obj["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        artist = obj["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""

        if title.isEmpty {
            title = "Nothing playing"
            artist = "Pick a genre from the ♫ menu"
        }

        let dur = (obj["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
        let elapsed = (obj["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
        duration = formatTime(dur)
        currentTime = formatTime(elapsed)
        progress = dur > 0 ? elapsed / dur : 0

        let rate = obj["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        isPlaying = rate == 1

        if let b64 = obj["kMRMediaRemoteNowPlayingInfoArtworkData"] as? String,
           let imgData = Data(base64Encoded: b64),
           let image = NSImage(data: imgData) {
            artwork = image
        }
    }

    func playPause() {
        _ = try? ShellHelper.run("nowplaying-cli", arguments: ["togglePlayPause"])
    }

    func next() {
        _ = try? ShellHelper.run("nowplaying-cli", arguments: ["next"])
    }

    func previous() {
        _ = try? ShellHelper.run("nowplaying-cli", arguments: ["previous"])
    }

    func seek(to seconds: Double) {
        _ = try? ShellHelper.run("nowplaying-cli", arguments: ["seek", "\(Int(seconds.rounded()))"])
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
