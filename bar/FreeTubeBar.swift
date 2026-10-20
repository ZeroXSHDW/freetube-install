import AppKit

// A minimal menu-bar controller for FreeTube.
// - Shows the current Now Playing title and Play/Pause / Next / Previous.
// - Lists every genre from the Top Charts manifest; clicking one deep-links
//   FreeTube to that genre's playlist and starts playing.

@main
struct FreeTubeBar {
    static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var nowPlayingItem: NSMenuItem?
    private var genres: [(name: String, playlistId: String, firstVideoId: String)] = []

    private var manifestPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/FreeTube/top-charts.json"
    }

    private var nowPlayingCLI: String {
        for candidate in ["/opt/homebrew/bin/nowplaying-cli", "/usr/local/bin/nowplaying-cli", "/opt/local/bin/nowplaying-cli"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "nowplaying-cli"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "♪"
        loadManifest()
        rebuildMenu()
    }

    // MARK: - Manifest

    private func loadManifest() {
        guard let data = FileManager.default.contents(atPath: manifestPath),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            genres = []
            return
        }
        genres = objects.compactMap { entry in
            guard let name = entry["name"] as? String,
                  let playlistId = entry["playlistId"] as? String,
                  let firstVideoId = entry["firstVideoId"] as? String else {
                return nil
            }
            return (name, playlistId, firstVideoId)
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "FreeTube", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let nowPlaying = NSMenuItem(title: "Now Playing: —", action: nil, keyEquivalent: "")
        nowPlaying.isEnabled = false
        nowPlayingItem = nowPlaying
        menu.addItem(nowPlaying)

        menu.addItem(.separator())

        menu.addItem(makeItem("Play / Pause", #selector(playPause)))
        menu.addItem(makeItem("Next Track", #selector(nextTrack)))
        menu.addItem(makeItem("Previous Track", #selector(previousTrack)))

        menu.addItem(.separator())

        if genres.isEmpty {
            let empty = NSMenuItem(title: "No Top Charts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let genresMenu = NSMenu(title: "Genres")
            for genre in genres {
                let item = NSMenuItem(title: genre.name, action: #selector(playGenre(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [genre.playlistId, genre.firstVideoId]
                genresMenu.addItem(item)
            }
            let genresItem = NSMenuItem(title: "Genres", action: nil, keyEquivalent: "")
            genresItem.submenu = genresMenu
            menu.addItem(genresItem)
        }

        menu.addItem(.separator())

        menu.addItem(makeItem("Open FreeTube", #selector(openFreeTube)))
        menu.addItem(makeItem("Refresh Genres", #selector(refreshGenres)))

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit FreeTube Bar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let title = run([nowPlayingCLI, "get", "title"])
        nowPlayingItem?.title = title.isEmpty ? "Now Playing: —" : "Now Playing: \(title)"
    }

    // MARK: - Actions

    @objc private func playPause() {
        _ = run([nowPlayingCLI, "togglePlayPause"])
    }

    @objc private func nextTrack() {
        _ = run([nowPlayingCLI, "next"])
    }

    @objc private func previousTrack() {
        _ = run([nowPlayingCLI, "previous"])
    }

    @objc private func openFreeTube() {
        _ = run(["/usr/bin/open", "-a", "FreeTube"])
    }

    @objc private func playGenre(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        let url = "https://www.youtube.com/watch?v=\(pair[1])&list=\(pair[0])"
        _ = run(["/usr/bin/open", "-a", "FreeTube", url])
    }

    @objc private func refreshGenres() {
        loadManifest()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Process helper

    @discardableResult
    private func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
