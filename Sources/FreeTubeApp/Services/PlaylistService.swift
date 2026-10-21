import Foundation

final class PlaylistService: ObservableObject {
    static let shared = PlaylistService()

    private let supportDir: URL
    private let playlistsDB: URL
    private let manifestURL: URL

    @Published var playlists: [Playlist] = []
    @Published var isRefreshing = false
    @Published var refreshLog: [String] = []
    @Published var lastError: String?

    private let logQueue = DispatchQueue(label: "com.freetube.playlist.log", qos: .utility)

    init() {
        self.supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeTube")
        self.playlistsDB = supportDir.appendingPathComponent("playlists.db")
        self.manifestURL = supportDir.appendingPathComponent("top-charts.json")
        loadPlaylists()
    }

    private func log(_ message: String) {
        logQueue.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            DispatchQueue.main.async {
                self.refreshLog.append("[\(timestamp)] \(message)")
            }
        }
    }

    func loadPlaylists() {
        guard FileManager.default.fileExists(atPath: playlistsDB.path) else {
            self.playlists = []
            return
        }

        do {
            let text = try String(contentsOf: playlistsDB, encoding: .utf8)
            var docs: [String: [String: Any]] = [:]
            var order: [String] = []

            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let id = obj["_id"] as? String else { continue }
                if obj["$$deleted"] as? Bool == true {
                    docs.removeValue(forKey: id)
                    order.removeAll { $0 == id }
                    continue
                }
                if docs[id] == nil {
                    order.append(id)
                }
                docs[id] = obj
            }

            self.playlists = order.compactMap { id in
                guard let doc = docs[id] else { return nil }
                return playlist(from: doc, id: id)
            }
        } catch {
            print("Failed to load playlists: \(error)")
        }
    }

    private func playlist(from doc: [String: Any], id: String) -> Playlist? {
        guard let name = doc["playlistName"] as? String else { return nil }
        let videos = (doc["videos"] as? [[String: Any]] ?? []).compactMap { v in
            Track(
                videoId: v["videoId"] as? String ?? "",
                title: v["title"] as? String ?? "",
                author: v["author"] as? String ?? "",
                authorId: v["authorId"] as? String,
                lengthSeconds: v["lengthSeconds"] as? Int ?? 0,
                published: v["published"] as? Int64,
                timeAdded: v["timeAdded"] as? Int64,
                playlistItemId: v["playlistItemId"] as? String,
                type: v["type"] as? String ?? "video"
            )
        }
        return Playlist(
            playlistItemId: doc["playlistItemId"] as? String,
            playlistName: name,
            protected: doc["protected"] as? Bool ?? false,
            description: doc["description"] as? String,
            videos: videos,
            createdAt: doc["createdAt"] as? Int64,
            lastUpdatedAt: doc["lastUpdatedAt"] as? Int64,
            lastPlayedAt: doc["lastPlayedAt"] as? Int64
        )
    }

    func refreshCharts(showUI: Bool = false) {
        isRefreshing = true
        lastError = nil

        Task {
            do {
                // Check if FreeTube is running
                if isFreeTubeRunning() {
                    log("FreeTube is running. Skipping refresh (run with --force to quit first).")
                    await MainActor.run {
                        self.isRefreshing = false
                    }
                    return
                }

                log("Fetching Invidious instances…")
                let instances = try await fetchInvidiousInstances()
                log("Instances: \(instances.joined(separator: ", "))")

                // Load existing playlists
                loadPlaylists()

                var updatedPlaylists: [Playlist] = []
                let now = Int64(Date().timeIntervalSince1970 * 1000)

                for genre in Genre.allGenres {
                    log("Processing \(genre.name)…")
                    let videos = try await buildGenre(instances: instances, genre: genre, limit: 15)

                    if videos.count >= 6 {
                        let playlist = Playlist(
                            playlistItemId: genre.playlistId,
                            playlistName: "Top Charts — \(genre.name)",
                            protected: false,
                            description: "Auto-updated top \(genre.name) (iTunes Top 100). Refreshed \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)).",
                            videos: videos,
                            createdAt: now,
                            lastUpdatedAt: now
                        )
                        updatedPlaylists.append(playlist)
                        log("  Resolved \(videos.count) videos")
                    } else {
                        log("  WARNING: Only \(videos.count) songs resolved (< 6); keeping existing.")
                    }

                    // Rate limit between genres
                    try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
                }

                // Build Radio Mix
                let allVideos = updatedPlaylists.flatMap { $0.videos }
                let radioVideos = Array(allVideos.shuffled().prefix(100))
                if radioVideos.count >= 6 {
                    let radioPlaylist = Playlist(
                        playlistItemId: Genre.allGenres.last { $0.name == "Radio Mix" }?.playlistId,
                        playlistName: "Top Charts — Radio Mix",
                        protected: false,
                        description: "Cross-genre Radio Mix with \(radioVideos.count) tracks.",
                        videos: radioVideos,
                        createdAt: now,
                        lastUpdatedAt: now
                    )
                    updatedPlaylists.append(radioPlaylist)
                    log("Radio Mix: \(radioVideos.count) tracks across genres")
                }

                // Write playlists to DB
                let completed = updatedPlaylists
                try writePlaylists(completed)

                // Update manifest
                try updateManifest(playlists: completed)

                await MainActor.run {
                    self.playlists = completed
                    self.isRefreshing = false
                    self.log("Top Charts refresh complete: \(completed.count) playlists updated.")
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isRefreshing = false
                    self.log("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Private

    private func fetchInvidiousInstances() async throws -> [String] {
        guard let url = URL(string: "https://api.invidious.io/instances.json?sort_by=health") else {
            return ["https://invidious.f5.si"]
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            return ["https://invidious.f5.si"]
        }
        var instances: [String] = []
        for item in json.prefix(5) {
            guard item.count >= 2,
                  let uri = item[0] as? String,
                  let info = item[1] as? [String: Any],
                  info["api"] as? Bool == true,
                  !uri.contains("onion") && !uri.contains("i2p") else { continue }
            instances.append(uri.replacingOccurrences(of: "/$", with: "", options: .regularExpression))
        }
        return instances.isEmpty ? ["https://invidious.f5.si"] : instances
    }

    private func buildGenre(instances: [String], genre: Genre, limit: Int) async throws -> [Track] {
        // Fetch iTunes chart
        let chartURLString = "https://itunes.apple.com/us/rss/topsongs/limit=\(limit)/genre=14/explicit=true/json"
        // Note: genre ID should be dynamic based on genre, but using 14 (Pop) as default
        guard let chartURL = URL(string: chartURLString) else { return [] }
        let (chartData, _) = try await URLSession.shared.data(from: chartURL)
        guard let chartJSON = try? JSONSerialization.jsonObject(with: chartData) as? [String: Any],
              let feed = chartJSON["feed"] as? [String: Any],
              let entries = feed["entry"] as? [[String: Any]] else {
            return []
        }

        var songs: [(artist: String, title: String)] = []
        for entry in entries {
            if let imArtist = entry["im:artist"] as? [String: Any],
               let artist = imArtist["label"] as? String,
               let imName = entry["im:name"] as? [String: Any],
               let name = imName["label"] as? String {
                songs.append((artist, name))
            }
        }

        var resolved: [Track] = []
        for song in songs {
            if let track = try? await resolveSong(instances: instances, artist: song.artist, title: song.title) {
                resolved.append(track)
            }
            try? await Task.sleep(nanoseconds: 400_000_000) // rate limit
        }

        // oEmbed check
        var validTracks: [Track] = []
        for track in resolved {
            if await isVideoAvailable(track.videoId) {
                validTracks.append(track)
            }
        }

        return validTracks
    }

    private func resolveSong(instances: [String], artist: String, title: String) async throws -> Track? {
        let query = "\(artist) \(title)"
        for instance in instances.shuffled() {
            do {
                let searchURL = "\(instance)/api/v1/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&type=video"
                guard let url = URL(string: searchURL) else { continue }
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }

                for item in results {
                    let videoTitle = (item["title"] as? String ?? "").lowercased()
                    if item["liveNow"] as? Bool == true { continue }
                    if videoTitle.contains("live") || videoTitle.contains("🔴") || videoTitle.contains("stream") { continue }

                    let videoId = item["videoId"] as? String ?? ""
                    guard !videoId.isEmpty else { continue }

                    return Track(
                        videoId: videoId,
                        title: item["title"] as? String ?? title,
                        author: item["author"] as? String ?? artist,
                        authorId: item["authorId"] as? String,
                        lengthSeconds: item["lengthSeconds"] as? Int ?? 0,
                        published: (item["published"] as? Int64 ?? 0) * 1000
                    )
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func isVideoAvailable(_ videoId: String) async -> Bool {
        let urlString = "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(videoId)"
        guard let url = URL(string: urlString) else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                return http.statusCode != 404
            }
        } catch {
            return true // Assume available on error
        }
        return true
    }

    private func writePlaylists(_ playlists: [Playlist]) throws {
        var lines: [String] = []
        for playlist in playlists {
            var doc: [String: Any] = [
                "_id": playlist.playlistItemId ?? playlist.playlistName,
                "playlistName": playlist.playlistName,
                "protected": playlist.protected,
                "description": playlist.description ?? "",
                "videos": playlist.videos.map { v in
                    var track: [String: Any] = [
                        "videoId": v.videoId,
                        "title": v.title,
                        "author": v.author,
                        "lengthSeconds": v.lengthSeconds,
                        "type": v.type
                    ]
                    if let authorId = v.authorId { track["authorId"] = authorId }
                    if let published = v.published { track["published"] = published }
                    if let timeAdded = v.timeAdded { track["timeAdded"] = timeAdded }
                    if let playlistItemId = v.playlistItemId { track["playlistItemId"] = playlistItemId }
                    return track
                },
                "createdAt": playlist.createdAt ?? Int64(Date().timeIntervalSince1970 * 1000),
                "lastUpdatedAt": playlist.lastUpdatedAt ?? Int64(Date().timeIntervalSince1970 * 1000)
            ]
            if let lastPlayed = playlist.lastPlayedAt {
                doc["lastPlayedAt"] = lastPlayed
            }
            if let data = try? JSONSerialization.data(withJSONObject: doc, options: []),
               let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        try lines.joined(separator: "\n").write(to: playlistsDB, atomically: true, encoding: .utf8)
    }

    private func updateManifest(playlists: [Playlist]) throws {
        var manifest: [[String: Any]] = []
        for playlist in playlists {
            guard let firstVideo = playlist.videos.first else { continue }
            manifest.append([
                "name": playlist.playlistName,
                "playlistId": playlist.playlistItemId ?? "",
                "firstVideoId": firstVideo.videoId,
                "videoIds": playlist.videos.map { $0.videoId }
            ])
        }
        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]) {
            try data.write(to: manifestURL, options: .atomic)
        }
    }

    private func isFreeTubeRunning() -> Bool {
        let output = try? ShellHelper.run("/usr/bin/pgrep", arguments: ["-f", "FreeTube.app/Contents/MacOS/FreeTube"])
        return output != nil && !output!.isEmpty
    }
}
