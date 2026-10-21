import Foundation

final class LaunchAgentService: ObservableObject {
    static let shared = LaunchAgentService()

    private let launchDir: URL
    private let uid: String

    @Published var agents: [LaunchAgentStatus] = []

    init() {
        self.launchDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        self.uid = String(getuid())
        refresh()
    }

    func refresh() {
        var statuses: [LaunchAgentStatus] = []
        for name in LaunchAgentName.allCases {
            let plistURL = launchDir.appendingPathComponent("\(name.rawValue).plist")
            let plistExists = FileManager.default.fileExists(atPath: plistURL.path)
            let isLoaded = isAgentLoaded(name.rawValue)
            statuses.append(LaunchAgentStatus(
                name: name,
                isLoaded: isLoaded,
                isEnabled: plistExists && isLoaded,
                plistExists: plistExists
            ))
        }
        self.agents = statuses
    }

    func enable(_ name: LaunchAgentName) {
        let plistURL = launchDir.appendingPathComponent("\(name.rawValue).plist")
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            print("Plist not found: \(plistURL.path)")
            return
        }
        _ = try? ShellHelper.run("/usr/bin/launchctl", arguments: ["bootout", "gui/\(uid)/\(name.rawValue)"])
        _ = try? ShellHelper.run("/usr/bin/launchctl", arguments: ["bootstrap", "gui/\(uid)", plistURL.path])
        _ = try? ShellHelper.run("/usr/bin/launchctl", arguments: ["enable", "gui/\(uid)/\(name.rawValue)"])
        refresh()
    }

    func disable(_ name: LaunchAgentName) {
        _ = try? ShellHelper.run("/usr/bin/launchctl", arguments: ["bootout", "gui/\(uid)/\(name.rawValue)"])
        _ = try? ShellHelper.run("/usr/bin/launchctl", arguments: ["disable", "gui/\(uid)/\(name.rawValue)"])
        refresh()
    }

    func restart(_ name: LaunchAgentName) {
        disable(name)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.enable(name)
        }
    }

    func toggle(_ name: LaunchAgentName) {
        if let status = agents.first(where: { $0.name == name }) {
            if status.isLoaded {
                disable(name)
            } else {
                enable(name)
            }
        }
    }

    private func isAgentLoaded(_ name: String) -> Bool {
        return (try? ShellHelper.run("/usr/bin/launchctl", arguments: ["print", "gui/\(uid)/\(name)"])) != nil
    }
}
