import Foundation
import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    let installation = InstallationService.shared
    let updateService = UpdateService.shared
    let playlistService = PlaylistService.shared
    let launchAgentService = LaunchAgentService.shared
    let audioService = AudioDeviceService.shared
    let configService = ConfigService.shared

    @Published var showingInstallView = false
    @Published var showingSettings = false
    @Published var showingGenres = false
    @Published var showingStatus = false

    func checkSystemHealth() {
        installation.checkForUpdates()
        playlistService.loadPlaylists()
        launchAgentService.refresh()
        audioService.currentDevice = audioService.getCurrentDevice()
    }

    var isFreeTubeInstalled: Bool {
        installation.currentVersion != nil
    }

    var currentVersionText: String {
        installation.currentVersion ?? "Not installed"
    }

    var latestVersionText: String {
        updateService.latestVersion ?? "Checking..."
    }

    var needsUpdate: Bool {
        updateService.updateAvailable
    }
}
