import Foundation

final class ConfigService: ObservableObject {
    static let shared = ConfigService()

    private let supportDir: URL

    @Published var config: AppConfig = AppConfig.defaultConfig
    @Published var isValid: Bool = false
    @Published var validationMessages: [String] = []

    init() {
        self.supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeTube")
        loadConfig()
    }

    private var settingsURL: URL {
        supportDir.appendingPathComponent("settings.db")
    }

    func loadConfig() {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            self.config = AppConfig.defaultConfig
            self.isValid = true
            self.validationMessages = ["No settings.db found; using defaults."]
            return
        }

        do {
            let text = try String(contentsOf: settingsURL, encoding: .utf8)
            var settings: [String: Any] = [:]
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                   let key = obj["_id"] as? String {
                    settings[key] = obj["value"]
                }
            }

            self.config = AppConfig(
                backendPreference: settings["backendPreference"] as? String ?? "local",
                backendFallback: settings["backendFallback"] as? Bool ?? true,
                useRssFeeds: settings["useRssFeeds"] as? Bool ?? true,
                autoplayPlaylists: settings["autoplayPlaylists"] as? Bool ?? true,
                autoplayVideos: settings["autoplayVideos"] as? Bool ?? true,
                playNextVideo: settings["playNextVideo"] as? Bool ?? true,
                defaultVideoFormat: settings["defaultVideoFormat"] as? String ?? "dash",
                defaultQuality: settings["defaultQuality"] as? String ?? "720",
                defaultAutoplayInterruptionIntervalHours: settings["defaultAutoplayInterruptionIntervalHours"] as? Int ?? 12,
                landingPage: settings["landingPage"] as? String ?? "userPlaylists",
                expandSideBar: settings["expandSideBar"] as? Bool ?? true,
                checkForUpdates: settings["checkForUpdates"] as? Bool ?? true,
                defaultProfile: settings["defaultProfile"] as? String ?? "allChannels",
                rememberHistory: settings["rememberHistory"] as? Bool ?? true,
                userPlaylistsSortBy: settings["userPlaylistsSortBy"] as? String ?? "latest_played_first"
            )
            self.isValid = true
            self.validationMessages = ["Configuration loaded successfully."]
        } catch {
            self.isValid = false
            self.validationMessages = ["Failed to load config: \(error.localizedDescription)"]
        }
    }

    func saveConfig() throws {
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try config.write(to: settingsURL)
        self.isValid = true
        self.validationMessages = ["Configuration saved."]
    }

    func resetToDefaults() {
        self.config = AppConfig.defaultConfig
        try? saveConfig()
    }

    var isLocalAPIPreferred: Bool {
        config.backendPreference == "local"
    }

    var isInvidiousFallbackEnabled: Bool {
        config.backendFallback
    }

    var areRSSFeedsEnabled: Bool {
        config.useRssFeeds
    }

    var defaultQuality: String {
        config.defaultQuality
    }
}
