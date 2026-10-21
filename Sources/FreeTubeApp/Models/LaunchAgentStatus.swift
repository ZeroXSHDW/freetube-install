import Foundation

enum LaunchAgentName: String, CaseIterable, Identifiable, Codable {
    case autoupdate = "local.freetube.autoupdate"
    case topmusic = "local.freetube.topmusic"
    case bar = "local.freetube.bar"
    case resume = "local.freetube.resume"
    case audiopause = "local.freetube.audiopause"
    case installer = "local.freetube.installer"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .autoupdate: return "FreeTube Auto-Updater"
        case .topmusic: return "Top Charts Refresher"
        case .bar: return "♫ FreeTubeBar Menu Bar"
        case .resume: return "Resume on Login"
        case .audiopause: return "AirPods Auto-Pause"
        case .installer: return "Native Swift Add-On"
        }
    }

    var description: String {
        switch self {
        case .autoupdate: return "Updates FreeTube at login and every 6 hours"
        case .topmusic: return "Refreshes 18 genre playlists every 6 hours"
        case .bar: return "Menu bar app with Now Playing popover"
        case .resume: return "Resumes last played genre on login"
        case .audiopause: return "Pauses FreeTube when headphones removed"
        case .installer: return "FreeTubeInstaller app (SponsorBlock, endless queue, ♫ menu bar)"
        }
    }
}

struct LaunchAgentStatus: Identifiable, Equatable {
    var id: String { name.rawValue }
    let name: LaunchAgentName
    var isLoaded: Bool = false
    var isEnabled: Bool = false
    var plistExists: Bool = false
}
