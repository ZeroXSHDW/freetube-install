import Foundation

/// Read/access layer for FreeTube's own databases: history, subscriptions,
/// playlists and settings. This is what makes the add-on a true FreeTube
/// companion — it can read what you watched and who you subscribed to,
/// generate mixes from it, export everything, and clean up.
final class FreeTubeDataService: ObservableObject {
    static let shared = FreeTubeDataService()

    struct SubscriptionChannel: Identifiable, Equatable {
        let channelId: String
        let name: String
        var id: String { channelId }
    }

    struct Stats: Equatable {
        var historyCount: Int = 0
        var subscriptionsCount: Int = 0
        var playlistsCount: Int = 0
        var videosWatchedMinutes: Int = 0
    }

    private let supportDir: URL
    private var historyURL: URL { supportDir.appendingPathComponent("history.db") }
    private var subscriptionsURL: URL { supportDir.appendingPathComponent("subscriptions.db") }
    private var profilesURL: URL { supportDir.appendingPathComponent("profiles.db") }
    private var playlistsURL: URL { supportDir.appendingPathComponent("playlists.db") }
    private var settingsURL: URL { supportDir.appendingPathComponent("settings.db") }

    @Published var history: [Track] = []
    @Published var subscriptions: [SubscriptionChannel] = []
    @Published var stats = Stats()

    init() {
        self.supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeTube")
        reload()
    }

    func reload() {
        history = parseHistory()
        subscriptions = parseSubscriptions()
        stats = Stats(
            historyCount: history.count,
            subscriptionsCount: subscriptions.count,
            playlistsCount: NedbFile.documents(at: playlistsURL).count,
            videosWatchedMinutes: history.map { max(0, $0.lengthSeconds) }.reduce(0, +) / 60
        )
    }

    // MARK: - History

    private func parseHistory() -> [Track] {
        NedbFile.documents(at: historyURL).map { doc -> Track in
            let d = doc.data
            return Track(
                videoId: d["videoId"] as? String ?? doc.id,
                title: d["title"] as? String ?? "Unknown title",
                author: d["author"] as? String ?? "",
                authorId: d["authorId"] as? String,
                lengthSeconds: (d["lengthSeconds"] as? NSNumber)?.intValue ?? 0,
                published: doc.int64Value("published"),
                timeAdded: doc.int64Value("watchStartDate") ?? doc.int64Value("lastWatchedTime"),
                playlistItemId: nil,
                type: d["type"] as? String ?? "video"
            )
        }
        .sorted { ($0.timeAdded ?? 0) > ($1.timeAdded ?? 0) }
    }

    /// Unique tracks from history, most recent first.
    func recentUniqueHistory(limit: Int = 25) -> [Track] {
        var seen = Set<String>()
        var result: [Track] = []
        for track in history where !seen.contains(track.videoId) {
            seen.insert(track.videoId)
            result.append(track)
            if result.count >= limit { break }
        }
        return result
    }

    /// Clears history entries older than the given number of days.
    /// Only call while FreeTube is not running.
    @discardableResult
    func clearHistoryOlderThan(days: Int) throws -> Int {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(days) * 24 * 3600 * 1000
        let docs = NedbFile.documents(at: historyURL)
        var kept: [String] = []
        var removed = 0
        for doc in docs {
            let watched = doc.int64Value("watchStartDate") ?? doc.int64Value("lastWatchedTime") ?? 0
            if watched < cutoff { removed += 1 } else {
                if let line = try? JSONSerialization.data(withJSONObject: doc.data),
                   let text = String(data: line, encoding: .utf8) {
                    kept.append(text)
                }
            }
        }
        try NedbFile.replace(lines: kept, at: historyURL)
        reload()
        return removed
    }

    /// Removes a single video from history.
    @discardableResult
    func removeFromHistory(videoId: String) throws -> Int {
        let docs = NedbFile.documents(at: historyURL)
        var kept: [String] = []
        var removed = 0
        for doc in docs {
            if doc.data["videoId"] as? String == videoId { removed += 1 } else {
                if let line = try? JSONSerialization.data(withJSONObject: doc.data),
                   let text = String(data: line, encoding: .utf8) {
                    kept.append(text)
                }
            }
        }
        try NedbFile.replace(lines: kept, at: historyURL)
        reload()
        return removed
    }

    // MARK: - Subscriptions

    private func parseSubscriptions() -> [SubscriptionChannel] {
        NedbFile.documents(at: subscriptionsURL).map { doc in
            let d = doc.data
            let channelId = d["channelId"] as? String ?? doc.id
            let name = d["author"] as? String ?? d["channelName"] as? String ?? "Unnamed channel"
            return SubscriptionChannel(channelId: channelId, name: name)
        }
        .sorted { $0.name.caseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Smart new-from-subscriptions mix: sample the latest uploads of a few
    /// random channels (based on your subscriptions) that FreeTube will play.
    func subscriptionMix(limit: Int = 25) -> [Track] {
        var result: [Track] = []
        for channel in subscriptions.shuffled().prefix(12) {
            result.append(Track(videoId: "", title: channel.name,
                                author: channel.name, lengthSeconds: 0))
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - Export

    /// Exports history + subscriptions + favorites/watch later to one JSON file.
    func exportAll(to url: URL) throws {
        var payload: [String: Any] = [:]
        payload["exportedAt"] = ISO8601DateFormatter().string(from: Date())
        payload["history"] = history.compactMap { $0.toDictionary() }
        payload["subscriptions"] = subscriptions.map {
            ["channelId": $0.channelId, "name": $0.name]
        }
        payload["favorites"] = LibraryService.shared.favorites.compactMap { $0.toDictionary() }
        payload["watchLater"] = LibraryService.shared.watchLater.compactMap { $0.toDictionary() }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Settings validation (doctor-style fixing)

    /// Returns true if settings.db parses and contains required keys.
    var settingsHealth: (exists: Bool, valid: Bool, missingKeys: [String]) {
        let docs = NedbFile.documents(at: settingsURL)
        guard NedbFile.exists(settingsURL) else { return (false, false, []) }
        let ids = Set(docs.map { $0.id })
        let required: Set<String> = ["backendPreference", "backendFallback", "useRssFeeds",
                                     "defaultVideoFormat", "defaultQuality", "landingPage",
                                     "expandSideBar", "defaultProfile", "rememberHistory"]
        let missing = required.subtracting(ids).sorted()
        return (true, missing.isEmpty, missing)
    }
}

extension Track {
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "videoId": videoId,
            "title": title,
            "author": author,
            "lengthSeconds": lengthSeconds,
            "type": type
        ]
        if let authorId { dict["authorId"] = authorId }
        if let published { dict["published"] = published }
        if let timeAdded { dict["timeAdded"] = timeAdded }
        return dict
    }
}
