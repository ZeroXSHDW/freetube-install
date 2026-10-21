import Foundation
import AppKit

enum InstallationError: Error, LocalizedError {
    case releaseNotFound
    case checksumMismatch(expected: String, actual: String)
    case codeSignVerificationFailed
    case downloadFailed
    case mountFailed
    case appNotFoundInDMG
    case installFailed

    var errorDescription: String? {
        switch self {
        case .releaseNotFound:
            return "No FreeTube release found for this architecture"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch. Expected: \(expected), Got: \(actual)"
        case .codeSignVerificationFailed:
            return "Code signature verification failed"
        case .downloadFailed:
            return "Download failed"
        case .mountFailed:
            return "Failed to mount DMG"
        case .appNotFoundInDMG:
            return "FreeTube.app not found inside DMG"
        case .installFailed:
            return "Installation failed"
        }
    }
}

struct ReleaseAsset: Codable {
    let tagName: String
    let version: String
    let assetName: String
    let downloadURL: String
    let digest: String
}

final class InstallationService: ObservableObject {
    static let shared = InstallationService()

    private let apiURL = "https://api.github.com/repos/FreeTubeApp/FreeTube/releases"
    let appDir: URL
    private let supportDir: URL

    @Published var isInstalling = false
    @Published var downloadProgress = DownloadProgress()
    @Published var installLog: [String] = []
    @Published var currentVersion: String?
    @Published var latestVersion: String?
    @Published var isUpToDate: Bool = false
    @Published var lastError: InstallationError?

    private let logQueue = DispatchQueue(label: "com.freetube.installer.log", qos: .utility)

    init() {
        self.appDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        self.supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FreeTube")
        checkCurrentVersion()
    }

    private func log(_ message: String) {
        logQueue.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            DispatchQueue.main.async {
                self.installLog.append("[\(timestamp)] \(message)")
            }
        }
    }

    // MARK: - Version Checking

    func checkCurrentVersion() {
        for candidate in [appDir.appendingPathComponent("FreeTube.app"),
                          URL(fileURLWithPath: "/Applications/FreeTube.app")] {
            if let version = CodeSignHelper.bundleVersion(candidate) {
                self.currentVersion = version
                break
            }
        }
    }

    func checkForUpdates(showUI: Bool = false) {
        Task {
            do {
                let release = try await fetchLatestRelease()
                await MainActor.run {
                    self.latestVersion = release.version
                    if let current = self.currentVersion {
                        self.isUpToDate = Version.compare(current, release.version) >= 0
                    } else {
                        self.isUpToDate = false
                    }
                }
                if showUI {
                    log("Checked for updates. Latest: \(release.version), Current: \(self.currentVersion ?? "none")")
                }
            } catch {
                await MainActor.run {
                    self.lastError = .releaseNotFound
                    log("Failed to check for updates: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Installation

    func install(force: Bool = false) async throws {
        await MainActor.run {
            self.isInstalling = true
            self.downloadProgress = DownloadProgress()
            self.lastError = nil
            self.installLog.removeAll()
        }

        defer {
            Task { @MainActor in
                self.isInstalling = false
            }
        }

        // Check if already installed at target version
        if !force, let current = currentVersion, let latest = latestVersion,
           Version.compare(current, latest) >= 0 {
            log("FreeTube \(current) is already installed. Skipping.")
            return
        }

        // Resolve release
        log("Resolving FreeTube release…")
        let release = try await fetchLatestRelease()

        // Quit running FreeTube
        quitRunningFreeTube()

        // Download DMG
        try await downloadDMG(from: release.downloadURL)

        // Verify checksum
        let dmgsURL = FileManager.default.temporaryDirectory.appendingPathComponent(release.assetName)
        if !release.digest.isEmpty {
            try SHA256Helper.verify(fileURL: dmgsURL, expectedDigest: release.digest)
            log("Checksum verified.")
        } else {
            log("No published digest for this release; relying on code-signature verification.")
        }

        // Mount DMG
        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("freetube-mount")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        try ShellHelper.run("/usr/bin/hdiutil", arguments: [
            "attach", "-nobrowse", "-readonly", "-quiet", "-mountpoint", mountPoint.path, dmgsURL.path
        ])
        defer {
            try? ShellHelper.run("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-quiet"])
        }

        let srcApp = mountPoint.appendingPathComponent("FreeTube.app")
        guard FileManager.default.fileExists(atPath: srcApp.path) else {
            throw InstallationError.appNotFoundInDMG
        }

        // Verify code signature
        try CodeSignHelper.verify(srcApp)
        log("Code signature verified.")

        // Stage and install
        let stageURL = FileManager.default.temporaryDirectory.appendingPathComponent("FreeTube.app")
        try? FileManager.default.removeItem(at: stageURL)
        try FileManager.default.copyItem(at: srcApp, to: stageURL)

        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let destURL = appDir.appendingPathComponent("FreeTube.app")

        if FileManager.default.fileExists(atPath: destURL.path) {
            let oldURL = appDir.appendingPathComponent("FreeTube.app.old-\(Date().timeIntervalSince1970)")
            try FileManager.default.moveItem(at: destURL, to: oldURL)
            defer { try? FileManager.default.removeItem(at: oldURL) }
        }

        try FileManager.default.moveItem(at: stageURL, to: destURL)

        // Remove quarantine
        try CodeSignHelper.removeQuarantine(destURL)

        // Final verification
        try CodeSignHelper.verify(destURL)

        await MainActor.run {
            self.currentVersion = release.version
            self.isUpToDate = true
            log("Installed FreeTube \(release.version) to \(destURL.path)")
        }
    }

    // MARK: - Download

    private func downloadDMG(from urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw InstallationError.downloadFailed
        }

        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(url.lastPathComponent)

        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw InstallationError.downloadFailed
        }

        let totalBytes = httpResponse.value(forHTTPHeaderField: "Content-Length")
            .flatMap { Int64($0) } ?? 0

        await MainActor.run {
            self.downloadProgress = DownloadProgress(totalBytes: totalBytes, downloadedBytes: 0, isDownloading: true)
        }

        try FileManager.default.moveItem(at: tempURL, to: destURL)

        await MainActor.run {
            self.downloadProgress = DownloadProgress(
                totalBytes: totalBytes,
                downloadedBytes: totalBytes,
                isDownloading: false
            )
        }
        log("Downloaded \(url.lastPathComponent).")
    }

    // MARK: - Helpers

    func fetchLatestRelease() async throws -> ReleaseAsset {
        guard let url = URL(string: "\(apiURL)?per_page=1") else {
            throw InstallationError.releaseNotFound
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw InstallationError.releaseNotFound
        }

        guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = releases.first else {
            throw InstallationError.releaseNotFound
        }
        return try parseAsset(from: first)
    }

    private func parseAsset(from json: [String: Any]) throws -> ReleaseAsset {
        guard let tagName = json["tag_name"] as? String else {
            throw InstallationError.releaseNotFound
        }
        let version = tagName.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-beta$", with: "", options: .regularExpression)

        let arch = ProcessInfo.processInfo.environment["ARCH"] ?? (ProcessInfo.processInfo.operatingSystemVersionString.contains("arm") ? "arm64" : "x64")
        let assetName = "freetube-\(version)-beta-mac-\(arch).dmg"

        guard let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == assetName }),
              let downloadURL = asset["browser_download_url"] as? String else {
            throw InstallationError.releaseNotFound
        }

        var digest = ""
        if let digestRaw = asset["digest"] as? String {
            digest = digestRaw.replacingOccurrences(of: "sha256:", with: "")
        }

        return ReleaseAsset(
            tagName: tagName,
            version: version,
            assetName: assetName,
            downloadURL: downloadURL,
            digest: digest
        )
    }

    private func quitRunningFreeTube() {
        let script = "tell application \"FreeTube\" to quit"
        _ = try? ShellHelper.run("/usr/bin/osascript", arguments: ["-e", script])

        // Wait up to 20 seconds
        for _ in 0..<40 {
            if !isFreeTubeRunning() { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func isFreeTubeRunning() -> Bool {
        let output = try? ShellHelper.run("/usr/bin/pgrep", arguments: ["-f", "FreeTube.app/Contents/MacOS/FreeTube"])
        return output != nil && !output!.isEmpty
    }

    func openFreeTube() {
        for candidate in [appDir.appendingPathComponent("FreeTube.app"),
                          URL(fileURLWithPath: "/Applications/FreeTube.app")] {
            if FileManager.default.fileExists(atPath: candidate.path) {
                NSWorkspace.shared.open(candidate)
                return
            }
        }
    }
}
