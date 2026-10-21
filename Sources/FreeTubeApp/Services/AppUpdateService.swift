import Foundation
import AppKit

/// Self-updater for the FreeTubeInstaller add-on itself: checks the project's
/// GitHub releases, downloads the published `FreeTubeInstaller-macOS.zip`,
/// de-quarantines it, installs it over `~/Applications/FreeTubeInstaller.app`,
/// and relaunches — so the add-on stays current just like FreeTube does.
@MainActor
final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    struct ReleaseInfo {
        let version: String
        let downloadURL: String
        let assetName: String
    }

    @Published var currentVersion: String
    @Published var latestVersion: String?
    @Published var updateAvailable = false
    @Published var isChecking = false
    @Published var isUpdating = false
    @Published var log: [String] = []
    @Published var lastError: String?

    private let apiURL = "https://api.github.com/repos/ZeroXSHDW/freetube-install/releases"
    private var latestDownloadURL: String?
    private var latestAssetName: String?
    private let logQueue = DispatchQueue(label: "com.freetube.appupdate.log", qos: .utility)

    private init() {
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        currentVersion = (bundleVersion?.isEmpty == false) ? bundleVersion! : "1.1.1"
    }

    private func log(_ message: String) {
        logQueue.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            DispatchQueue.main.async {
                self.log.append("[\(timestamp)] \(message)")
                if self.log.count > 200 { self.log.removeFirst(self.log.count - 200) }
            }
        }
    }

    // MARK: - Check

    func check() async {
        isChecking = true
        defer { isChecking = false }

        guard let release = await fetchRelease() else {
            lastError = "No FreeTubeInstaller release found on GitHub"
            return
        }
        latestVersion = release.version
        latestDownloadURL = release.downloadURL
        latestAssetName = release.assetName
        updateAvailable = Version.compare(release.version, currentVersion) > 0
        log("Checked for add-on updates: current \(currentVersion), latest \(release.version)" +
            (updateAvailable ? " — update available" : " — up to date"))
    }

    private func fetchRelease() async -> ReleaseInfo? {
        guard let url = URL(string: "\(apiURL)/latest") else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { ($0["name"] as? String) == "FreeTubeInstaller-macOS.zip" }),
                  let downloadURL = asset["browser_download_url"] as? String else {
                return nil
            }
            let version = tagName.replacingOccurrences(of: "^v", with: "", options: .regularExpression)
            return ReleaseInfo(version: version, downloadURL: downloadURL, assetName: "FreeTubeInstaller-macOS.zip")
        } catch {
            return nil
        }
    }

    // MARK: - Apply update

    func update() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        lastError = nil

        // Resolve the download URL (re-check if we don't have it yet).
        var release: ReleaseInfo?
        if let urlString = latestDownloadURL, let name = latestAssetName, let version = latestVersion {
            release = ReleaseInfo(version: version, downloadURL: urlString, assetName: name)
        } else {
            release = await fetchRelease()
        }
        guard let release else {
            lastError = "Could not resolve the update download URL"
            return
        }

        log("Downloading FreeTubeInstaller \(release.version)…")
        guard let zipURL = URL(string: release.downloadURL) else {
            lastError = "Invalid download URL"
            return
        }

        do {
            let (tempFile, response) = try await URLSession.shared.download(from: zipURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                lastError = "Download failed"
                return
            }

            let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("ftapp-update")
            try? FileManager.default.removeItem(at: extractDir)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            log("Extracting…")
            _ = try ShellHelper.run("/usr/bin/unzip", arguments: ["-o", "-q", tempFile.path, "-d", extractDir.path])

            guard let newApp = findApp(named: "FreeTubeInstaller.app", in: extractDir) else {
                lastError = "FreeTubeInstaller.app not found in the update archive"
                return
            }

            let destDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            let dest = destDir.appendingPathComponent("FreeTubeInstaller.app")
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

            // Replace the running app (rename old, install new, remove old).
            if FileManager.default.fileExists(atPath: dest.path) {
                let old = destDir.appendingPathComponent("FreeTubeInstaller.app.old")
                try? FileManager.default.removeItem(at: old)
                try FileManager.default.moveItem(at: dest, to: old)
            }
            try FileManager.default.copyItem(at: newApp, to: dest)
            try CodeSignHelper.removeQuarantine(dest)
            _ = try? ShellHelper.run("/usr/bin/codesign", arguments: ["--force", "--deep", "--sign", "-", dest.path])

            currentVersion = release.version
            updateAvailable = false
            log("Updated to FreeTubeInstaller \(release.version). Relaunching…")

            // Launch the new app, then quit this instance.
            NSWorkspace.shared.open(dest)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApp.terminate(nil)
            }
        } catch {
            lastError = error.localizedDescription
            log("Update failed: \(error.localizedDescription)")
        }
    }

    private func findApp(named name: String, in dir: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let file as URL in enumerator where file.lastPathComponent == name {
            return file
        }
        return nil
    }
}
