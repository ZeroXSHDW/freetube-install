import Foundation

/// Persisted favorites & watch-later lists. Shares the exact same files as
/// FreeTubeBar (`favorites.json` / `watchLater.json` in
/// `~/Library/Application Support/FreeTube/`), so the two never diverge.
final class LibraryService: ObservableObject {
    static let shared = LibraryService()

    private let supportDir: URL
    private let favoritesURL: URL
    private let watchLaterURL: URL

    @Published var favorites: [Track] = []
    @Published var watchLater: [Track] = []

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.supportDir = home.appendingPathComponent("Library/Application Support/FreeTube")
        self.favoritesURL = supportDir.appendingPathComponent("favorites.json")
        self.watchLaterURL = supportDir.appendingPathComponent("watchLater.json")
        load()
    }

    func load() {
        favorites = Self.readTracks(from: favoritesURL)
        watchLater = Self.readTracks(from: watchLaterURL)
    }

    func isFavorite(_ videoId: String) -> Bool {
        favorites.contains { $0.videoId == videoId }
    }

    func isWatchLater(_ videoId: String) -> Bool {
        watchLater.contains { $0.videoId == videoId }
    }

    func toggleFavorite(_ track: Track) {
        if isFavorite(track.videoId) {
            favorites.removeAll { $0.videoId == track.videoId }
        } else {
            favorites.insert(track, at: 0)
        }
        save(favorites, to: favoritesURL)
    }

    func toggleWatchLater(_ track: Track) {
        if isWatchLater(track.videoId) {
            watchLater.removeAll { $0.videoId == track.videoId }
        } else {
            watchLater.insert(track, at: 0)
        }
        save(watchLater, to: watchLaterURL)
    }

    func removeFromFavorites(_ videoId: String) {
        favorites.removeAll { $0.videoId == videoId }
        save(favorites, to: favoritesURL)
    }

    func removeFromWatchLater(_ videoId: String) {
        watchLater.removeAll { $0.videoId == videoId }
        save(watchLater, to: watchLaterURL)
    }

    // MARK: - Persistence

    private func save(_ tracks: [Track], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(tracks)
            try data.write(to: url, options: .atomic)
        } catch {
            print("LibraryService save failed: \(error)")
        }
    }

    private static func readTracks(from url: URL) -> [Track] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Track].self, from: data)) ?? []
    }
}
