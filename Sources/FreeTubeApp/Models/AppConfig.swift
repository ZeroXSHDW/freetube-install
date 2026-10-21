import Foundation

struct AppConfig: Codable {
    var backendPreference: String = "local"
    var backendFallback: Bool = true
    var useRssFeeds: Bool = true
    var autoplayPlaylists: Bool = true
    var autoplayVideos: Bool = true
    var playNextVideo: Bool = true
    var defaultVideoFormat: String = "dash"
    var defaultQuality: String = "720"
    var defaultAutoplayInterruptionIntervalHours: Int = 12
    var landingPage: String = "userPlaylists"
    var expandSideBar: Bool = true
    var checkForUpdates: Bool = true
    var defaultProfile: String = "allChannels"
    var rememberHistory: Bool = true
    var userPlaylistsSortBy: String = "latest_played_first"

    static let defaultConfig = AppConfig()

    func write(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
}
