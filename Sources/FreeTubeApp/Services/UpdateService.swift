import Foundation

final class UpdateService: ObservableObject {
    static let shared = UpdateService()
    private let installation = InstallationService.shared

    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var currentVersion: String?

    func checkForUpdates(showUI: Bool = false) {
        isChecking = true
        Task {
            do {
                let release = try await installation.fetchLatestRelease()
                await MainActor.run {
                    self.latestVersion = release.version
                    self.currentVersion = installation.currentVersion
                    if let current = installation.currentVersion {
                        self.updateAvailable = Version.compare(current, release.version) < 0
                    } else {
                        self.updateAvailable = true
                    }
                    self.isChecking = false
                    if showUI {
                        print("Update check: latest \(release.version), current \(installation.currentVersion ?? "none"), available: \(self.updateAvailable)")
                    }
                }
            } catch {
                await MainActor.run {
                    self.isChecking = false
                }
            }
        }
    }

    func applyUpdate(force: Bool = false) async {
        do {
            try await installation.install(force: force)
        } catch {
            print("Update failed: \(error.localizedDescription)")
        }
    }
}
