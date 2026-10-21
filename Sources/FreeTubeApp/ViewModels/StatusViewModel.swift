import Foundation
import SwiftUI

@MainActor
final class StatusViewModel: ObservableObject {
    let installation = InstallationService.shared
    let playlistService = PlaylistService.shared
    let launchAgentService = LaunchAgentService.shared
    let audioService = AudioDeviceService.shared
    let configService = ConfigService.shared

    @Published var showingDoctorOutput = false
    @Published var doctorOutput: String = ""

    func runDoctor() {
        var output: [String] = []

        output.append("=== FreeTube Status ===")
        output.append("")

        // App
        if let app = InstallationService.shared.appDir.appendingPathComponent("FreeTube.app") as URL?,
           FileManager.default.fileExists(atPath: app.path) {
            let version = CodeSignHelper.bundleVersion(app) ?? "unknown"
            output.append("✅ FreeTube.app v\(version) at \(app.path)")
        } else {
            output.append("❌ FreeTube.app not found")
        }

        // LaunchAgents
        output.append("")
        output.append("=== LaunchAgents ===")
        for agent in launchAgentService.agents {
            let status = agent.isLoaded ? "✅ loaded" : "❌ not loaded"
            output.append("  \(status) \(agent.name.displayName)")
        }

        // Playlists
        output.append("")
        output.append("=== Playlists ===")
        output.append("  \(playlistService.playlists.count) playlists")
        for pl in playlistService.playlists.prefix(10) {
            output.append("  • \(pl.playlistName) — \(pl.trackCount) tracks")
        }

        // Config
        output.append("")
        output.append("=== Config ===")
        output.append("  Backend: \(configService.config.backendPreference)")
        output.append("  Fallback: \(configService.config.backendFallback)")
        output.append("  RSS: \(configService.config.useRssFeeds)")
        output.append("  Quality: \(configService.config.defaultQuality)")

        // Audio
        output.append("")
        output.append("=== Audio ===")
        if let device = audioService.currentDevice {
            output.append("  Device: \(device.name)")
            output.append("  Headphones: \(device.isHeadphones)")
            output.append("  Built-in: \(device.isBuiltin)")
        } else {
            output.append("  Device: unknown")
        }

        doctorOutput = output.joined(separator: "\n")
        showingDoctorOutput = true
    }
}
