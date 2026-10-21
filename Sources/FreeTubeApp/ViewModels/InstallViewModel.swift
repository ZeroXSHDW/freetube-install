import Foundation
import SwiftUI

@MainActor
final class InstallViewModel: ObservableObject {
    let installation = InstallationService.shared

    @Published var showingForceInstall = false

    func install() {
        Task {
            try? await installation.install(force: false)
        }
    }

    func forceInstall() {
        Task {
            try? await installation.install(force: true)
        }
    }

    func checkUpdates() {
        installation.checkForUpdates()
    }

    var canInstall: Bool {
        !installation.isInstalling
    }

    var installButtonText: String {
        if installation.isInstalling {
            return "Installing…"
        }
        if installation.currentVersion == installation.latestVersion {
            return "Already up to date"
        }
        return "Install FreeTube"
    }
}
