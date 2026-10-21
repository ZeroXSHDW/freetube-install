import Foundation
import SwiftUI
import AppKit

/// The playback brain of the app: it watches system-wide Now Playing info,
/// manages an endless genre queue, keeps favorites in sync with FreeTubeBar and
/// applies SponsorBlock auto-skip. All playback happens inside FreeTube — the
/// app drives it through `freetube://` deep links and the system media controls.
@MainActor
final class NowPlayingViewModel: ObservableObject {
    static let shared = NowPlayingViewModel()

    @Published var title = "Nothing playing"
    @Published var artist = ""
    @Published var artwork: NSImage?
    @Published var isPlaying = false
    @Published var currentTime = "0:00"
    @Published var duration = "0:00"
    @Published var elapsedSeconds: Double = 0
    @Published var durationSeconds: Double = 0
    @Published var progress: Double = 0

    /// Queue driven by the selected genre's Top Charts playlist.
    @Published var queue: [Track] = []
    @Published var queueIndex: Int = -1
    @Published var currentGenre: Genre?
    @Published var endlessMode: Bool {
        didSet { UserDefaults.standard.set(endlessMode, forKey: "playback.endlessMode") }
    }
    @Published var isFavorite = false
    @Published var isWatchLater = false
    @Published var nowPlayingCLIInstalled: Bool = true

    private var timer: Timer?
    private var nowPlayingCLIPath: String?
    private var lastAdvanceAt: Date = .distantPast
    private var lastMatchedVideoId: String?

    private init() {
        endlessMode = UserDefaults.standard.object(forKey: "playback.endlessMode") as? Bool ?? true
        nowPlayingCLIPath = ShellHelper.resolveExecutable("nowplaying-cli")
        nowPlayingCLIInstalled = (nowPlayingCLIPath != nil)
        // Prefill queue with the genre playing last time.
        if let lastGenreId = UserDefaults.standard.string(forKey: "playback.lastGenreId") {
            if let genre = Genre.allGenres.first(where: { $0.playlistId == lastGenreId }) {
                _ = tryLoadQueue(for: genre)
            }
        }
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
        PowerEventsService.shared.activate()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Queue

    @discardableResult
    func tryLoadQueue(for genre: Genre) -> Bool {
        guard let playlist = PlaylistService.shared.playlists.first(where: {
            $0.playlistName == "Top Charts — \(genre.name)"
        }), !playlist.videos.isEmpty else {
            return false
        }
        currentGenre = genre
        queue = playlist.videos
        UserDefaults.standard.set(genre.playlistId, forKey: "playback.lastGenreId")
        return true
    }

    func playGenre(_ genre: Genre) {
        if !tryLoadQueue(for: genre) {
            _ = tryLoadQueue(for: genre)
            if queue.isEmpty {
                title = "Charts for \(genre.name) not ready"
                artist = "Run the Refresh Charts action first"
                queue = []
                queueIndex = -1
                return
            }
        }
        queueIndex = 0
        playIndex(0)
    }

    func playIndex(_ index: Int) {
        guard queue.indices.contains(index) else { return }
        queueIndex = index
        let track = queue[index]
        SponsorBlockService.shared.reset(for: track.videoId)
        DeepLinkService.shared.openVideo(track.videoId)
        title = "Loading in FreeTube…"
        artist = "\(track.author.isEmpty ? genreDisplayName : track.author)"
        isPlaying = false
    }

    func next() {
        guard !queue.isEmpty else { return }
        let next = (queueIndex + 1) % queue.count
        playIndex(next)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        let prev = queueIndex <= 0 ? queue.count - 1 : queueIndex - 1
        playIndex(prev)
    }

    var genreDisplayName: String {
        currentGenre?.name ?? ""
    }

    // MARK: - Polling

    private func poll() {
        guard let path = nowPlayingCLIPath else {
            nowPlayingCLIInstalled = false
            title = "Support limitation"
            artist = "Install nowplaying-cli: brew install nowplaying-cli"
            return
        }
        nowPlayingCLIInstalled = true

        guard let output = try? ShellHelper.run(path, arguments: ["get-raw"]),
              let data = output.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let newTitle = obj["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        if !newTitle.isEmpty {
            title = newTitle
            artist = obj["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? obj["kMRMediaRemoteNowPlayingInfoAlbumTitle"] as? String ?? ""
        }

        let newDuration = (obj["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
        let newElapsed = (obj["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
        durationSeconds = newDuration
        elapsedSeconds = newElapsed
        currentTime = formatTime(newElapsed)
        duration = formatTime(newDuration)
        progress = newDuration > 0 ? min(1, newElapsed / newDuration) : 0

        let rate = obj["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber
        let playState = rate?.doubleValue ?? obj["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        isPlaying = playState > 0

        if let b64 = obj["kMRMediaRemoteNowPlayingInfoArtworkData"] as? String,
           let imgData = Data(base64Encoded: b64),
           let image = NSImage(data: imgData) {
            artwork = image
        } else {
            artwork = nil
        }

        syncQueueFromTitle(newTitle)
        syncPinnedState()
        runSponsorIfPossible()
        maybeAutoAdvance()
    }

    // MARK: - Queue matching (so SponsorBlock + endless work even when the user
    // plays manually inside FreeTube)

    private func syncQueueFromTitle(_ title: String) {
        guard !title.isEmpty, !queue.isEmpty else { return }
        if let track = queue.first(where: { $0.title.lowercased() == title.lowercased() }),
           track.videoId != lastMatchedVideoId {
            guard let index = queue.firstIndex(where: { $0.videoId == track.videoId }) else { return }
            if queueIndex != index {
                queueIndex = index
                SponsorBlockService.shared.reset(for: track.videoId)
            }
            lastMatchedVideoId = track.videoId
        }
    }

    private var currentVideoId: String? {
        if queue.indices.contains(queueIndex) { return queue[queueIndex].videoId }
        return lastMatchedVideoId
    }

    private var currentTrack: Track? {
        queue.indices.contains(queueIndex) ? queue[queueIndex] : nil
    }

    // MARK: - SponsorBlock

    private func runSponsorIfPossible() {
        guard let videoId = currentVideoId else { return }
        SponsorBlockService.shared.observe(elapsed: elapsedSeconds, videoId: videoId)
    }

    // MARK: - Endless auto-advance

    private func maybeAutoAdvance() {
        guard endlessMode else { return }
        guard durationSeconds > 0,
              elapsedSeconds >= durationSeconds - 1.2,
              elapsedSeconds > 0,
              !queue.isEmpty else { return }
        guard Date().timeIntervalSince(lastAdvanceAt) > 10 else { return }
        lastAdvanceAt = Date()
        next()
    }

    // MARK: - Transport

    func playPause() {
        _ = try? ShellHelper.runNamed("nowplaying-cli", arguments: ["togglePlayPause"])
    }

    func seek(to seconds: Double) {
        _ = try? ShellHelper.runNamed("nowplaying-cli", arguments: ["seek", "\(Int(seconds.rounded()))"])
    }

    // MARK: - Favorites

    func toggleFavorite() {
        guard let track = pinnedTrack else { return }
        LibraryService.shared.toggleFavorite(track)
        isFavorite = LibraryService.shared.isFavorite(track.videoId)
    }

    func toggleWatchLater() {
        guard let track = pinnedTrack else { return }
        LibraryService.shared.toggleWatchLater(track)
        isWatchLater = LibraryService.shared.isWatchLater(track.videoId)
    }

    private var pinnedTrack: Track? {
        if let track = currentTrack { return track }
        guard let videoId = lastMatchedVideoId else { return nil }
        let author = artist
        return Track(videoId: videoId, title: title, author: author)
    }

    private func syncPinnedState() {
        guard let videoId = (currentTrack?.videoId ?? lastMatchedVideoId) else {
            isFavorite = false; isWatchLater = false; return
        }
        isFavorite = LibraryService.shared.isFavorite(videoId)
        isWatchLater = LibraryService.shared.isWatchLater(videoId)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
