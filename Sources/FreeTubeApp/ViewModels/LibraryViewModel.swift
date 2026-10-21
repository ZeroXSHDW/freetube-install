import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    let data = FreeTubeDataService.shared
    let library = LibraryService.shared
    let charts = PlaylistService.shared
    let deepLink = DeepLinkService.shared

    enum Section: String, CaseIterable {
        case favorites = "♥ Favorites"
        case watchLater = "🕓 Watch Later"
        case history = "⏱ History"
        case subscriptions = "👥 Subscriptions"
    }

    @Published var section: Section = .favorites
    @Published var statusLine: String?

    func reload() {
        charts.loadPlaylists()
        data.reload()
        library.load()
    }

    var freeTubeRunning: Bool {
        guard let out = try? ShellHelper.run("/usr/bin/pgrep",
                                            arguments: ["-f", "FreeTube.app/Contents/MacOS/FreeTube"]) else {
            return false
        }
        return !out.isEmpty
    }

    // MARK: - Row actions

    func open(_ track: Track) {
        deepLink.openVideo(track.videoId)
    }

    func openChannel(_ channel: FreeTubeDataService.SubscriptionChannel) {
        deepLink.openChannel(channel.channelId)
    }

    func toggleFavorite(_ track: Track) { library.toggleFavorite(track) }
    func toggleWatchLater(_ track: Track) { library.toggleWatchLater(track) }

    func playFavorites() {
        guard !library.favorites.isEmpty else { return }
        let vm = NowPlayingViewModel.shared
        vm.queue = library.favorites
        vm.currentGenre = nil
        vm.playIndex(0)
        statusLine = "Playing \(library.favorites.count) favorites"
    }

    // MARK: - Maintenance

    func clearHistory(olderThanDays: Int) {
        guard !freeTubeRunning else {
            statusLine = "Quit FreeTube first before cleaning history"
            return
        }
        do {
            let removed = try data.clearHistoryOlderThan(days: olderThanDays)
            statusLine = "Removed \(removed) history entries older than \(olderThanDays) days"
        } catch {
            statusLine = "History cleanup failed: \(error.localizedDescription)"
        }
    }

    func removeFromHistory(_ track: Track) {
        guard !freeTubeRunning else {
            statusLine = "Quit FreeTube first"
            return
        }
        do {
            try data.removeFromHistory(videoId: track.videoId)
        } catch {
            statusLine = "Remove failed: \(error.localizedDescription)"
        }
    }

    func exportAll() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "FreeTube-export.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try self.data.exportAll(to: url)
                Task { @MainActor in
                    self.statusLine = "Exported to \(url.lastPathComponent)"
                }
            } catch {
                Task { @MainActor in
                    self.statusLine = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
