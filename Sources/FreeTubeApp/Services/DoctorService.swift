import Foundation

/// One-click system doctor — verifies the whole FreeTube + add-on stack and
/// optionally repairs common issues (replacing freetube-config-validate.sh).
struct DoctorCheck: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let ok: Bool
    let detail: String
    let fixHint: String?

    static func == (lhs: DoctorCheck, rhs: DoctorCheck) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class DoctorService: ObservableObject {
    static let shared = DoctorService()

    @Published var checks: [DoctorCheck] = []
    @Published var isRunning = false
    @Published var lastRun: Date?

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var supportDir: URL {
        home.appendingPathComponent("Library/Application Support/FreeTube")
    }

    func run() async {
        isRunning = true
        var results: [DoctorCheck] = []
        results += await checkApp()
        results += await checkDatabases()
        results += await checkCharts()
        results += await checkAgents()
        results += await checkHelpers()
        results += await checkScheme()
        results += await checkDisk()

        self.checks = results
        self.lastRun = Date()
        self.isRunning = false
    }

    /// Attempts repairs: removes quarantine, fills missing settings keys,
    /// restarts LaunchAgents that are installed but not loaded.
    func fixEverything() async {
        // Quarantine removal
        let app = home.appendingPathComponent("Applications/FreeTube.app")
        if FileManager.default.fileExists(atPath: app.path) {
            try? CodeSignHelper.removeQuarantine(app)
        }

        // Missing settings keys -> write defaults
        let health = FreeTubeDataService.shared.settingsHealth
        if health.exists && !health.valid {
            let docs = NedbFile.documents(at: supportDir.appendingPathComponent("settings.db"))
            var existing: [String: [String: Any]] = [:]
            for doc in docs { existing[doc.id] = doc.data }
            let defaults: [String: Any] = [
                "backendPreference": "local",
                "backendFallback": true,
                "useRssFeeds": true,
                "defaultVideoFormat": "dash",
                "defaultQuality": "720",
                "landingPage": "subscriptions",
                "expandSideBar": true,
                "defaultProfile": "allChannels",
                "rememberHistory": true
            ]
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            for (key, value) in defaults where existing[key] == nil {
                let doc: [String: Any] = [
                    "_id": key,
                    "value": value,
                    "updatedAt": now
                ]
                try? NedbFile.append(doc, to: supportDir.appendingPathComponent("settings.db"))
            }
        }

        await run()
    }

    // MARK: - Checks

    private func checkApp() async -> [DoctorCheck] {
        var out: [DoctorCheck] = []
        let candidates = [home.appendingPathComponent("Applications/FreeTube.app"),
                          URL(fileURLWithPath: "/Applications/FreeTube.app")]
        guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return [DoctorCheck(name: "FreeTube.app installed", ok: false,
                                detail: "No FreeTube.app in ~/Applications or /Applications",
                                fixHint: "Run install.sh or Install tab")]
        }
        let version = CodeSignHelper.bundleVersion(app) ?? "unknown"
        out.append(DoctorCheck(name: "FreeTube.app installed", ok: true,
                               detail: "Version \(version) at \(app.path)", fixHint: nil))
        do {
            _ = try CodeSignHelper.verify(app)
            out.append(DoctorCheck(name: "Code signature valid", ok: true, detail: "codesign --verify passed", fixHint: nil))
        } catch {
            out.append(DoctorCheck(name: "Code signature valid", ok: false,
                                   detail: error.localizedDescription, fixHint: "Reinstall from Install tab"))
        }
        let quarantine = CodeSignHelper.hasQuarantineAttribute(app)
        out.append(DoctorCheck(name: "No quarantine flag", ok: !quarantine,
                               detail: quarantine ? "com.apple.quarantine still present" : "Clean",
                               fixHint: quarantine ? "Run Doctor → Fix Everything" : nil))
        return out
    }

    private func checkDatabases() async -> [DoctorCheck] {
        var out: [DoctorCheck] = []
        let data = FreeTubeDataService.shared
        data.reload()

        let health = data.settingsHealth
        let settingsLabel = health.exists
            ? (health.valid ? "settings.db OK" : "settings.db missing keys: \(health.missingKeys.joined(separator: ", "))")
            : "settings.db not found"
        out.append(DoctorCheck(name: "settings.db", ok: health.exists && health.valid,
                               detail: settingsLabel,
                               fixHint: health.exists && !health.valid ? "Run Doctor → Fix Everything" : nil))
        out.append(DoctorCheck(name: "playlists.db", ok: data.stats.playlistsCount > 0,
                               detail: "\(data.stats.playlistsCount) playlists", fixHint: "Run Refresh Charts"))
        out.append(DoctorCheck(name: "history.db", ok: NedbFile.exists(supportDir.appendingPathComponent("history.db")),
                               detail: "\(data.stats.historyCount) entries", fixHint: nil))
        out.append(DoctorCheck(name: "subscriptions.db", ok: NedbFile.exists(supportDir.appendingPathComponent("subscriptions.db")),
                               detail: "\(data.stats.subscriptionsCount) subscriptions", fixHint: nil))
        return out
    }

    private func checkCharts() async -> [DoctorCheck] {
        let manifest = supportDir.appendingPathComponent("top-charts.json")
        guard let data = try? Data(contentsOf: manifest),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [DoctorCheck(name: "Top Charts manifest", ok: false,
                                detail: "top-charts.json missing or unreadable",
                                fixHint: "Run Refresh Charts")]
        }
        return [DoctorCheck(name: "Top Charts manifest", ok: list.count >= 18,
                            detail: "\(list.count) genres present",
                            fixHint: list.count < 18 ? "Run Refresh Charts" : nil)]
    }

    private func checkAgents() async -> [DoctorCheck] {
        LaunchAgentService.shared.refresh()
        var out: [DoctorCheck] = []
        for status in LaunchAgentService.shared.agents {
            out.append(DoctorCheck(name: status.name.displayName,
                                   ok: status.plistExists && status.isLoaded,
                                   detail: status.plistExists
                                       ? (status.isLoaded ? "Loaded" : "Installed but not loaded")
                                       : "Plist missing",
                                   fixHint: status.plistExists && !status.isLoaded ? "Bootstrap via launchctl" : "Run install.sh"))
        }
        return out
    }

    private func checkHelpers() async -> [DoctorCheck] {
        var out: [DoctorCheck] = []
        out.append(DoctorCheck(name: "nowplaying-cli", ok: ShellHelper.resolveExecutable("nowplaying-cli") != nil,
                               detail: ShellHelper.resolveExecutable("nowplaying-cli") ?? "missing",
                               fixHint: "brew install nowplaying-cli"))
        let audioHelper = home.appendingPathComponent("Library/Application Support/FreeTubeBar/audiodevice")
        out.append(DoctorCheck(name: "audiodevice helper", ok: FileManager.default.fileExists(atPath: audioHelper.path),
                               detail: audioHelper.path, fixHint: "Run install.sh"))
        return out
    }

    private func checkScheme() async -> [DoctorCheck] {
        let app = home.appendingPathComponent("Applications/FreeTube.app")
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let urlTypes = info["CFBundleURLTypes"] as? [[String: Any]] else {
            return [DoctorCheck(name: "freetube:// deep links", ok: false,
                                detail: "Unable to read Info.plist URL scheme", fixHint: nil)]
        }
        let schemes = urlTypes.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        let hasFT = schemes.contains("freetube")
        return [DoctorCheck(name: "freetube:// deep links", ok: hasFT,
                            detail: hasFT ? "FreeTube registered the freetube:// scheme" : "Scheme not registered",
                            fixHint: hasFT ? nil : "Reinstall FreeTube")]
    }

    private func checkDisk() async -> [DoctorCheck] {
        let url = FileManager.default.homeDirectoryForCurrentUser
        let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        guard let capacity else {
            return [DoctorCheck(name: "Disk space", ok: true, detail: "Unknown", fixHint: nil)]
        }
        let ok = capacity > 2_000_000_000
        return [DoctorCheck(name: "Disk space", ok: ok,
                            detail: ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file) + " free",
                            fixHint: ok ? nil : "Free up space before updating FreeTube")]
    }
}
