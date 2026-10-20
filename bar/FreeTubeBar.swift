import AppKit

// FreeTubeBar — a native menu-bar controller for FreeTube.
//
// Left-click the ♫ icon for a Now Playing popover (album art, title, artist,
// progress, transport, shuffle). Right-click for the full menu (genres,
// shuffle, resume-on-login toggle, etc.).

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
    struct Genre {
        let name: String
        let playlistId: String
        let firstVideoId: String
        let videoIds: [String]
    }

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var nowPlayingItem: NSMenuItem?
    private var resumeItem: NSMenuItem!
    private var genres: [Genre] = []
    private let popover = NSPopover()
    private let playerVC = PlayerViewController()

    private var supportDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/FreeTube"
    }
    private var manifestPath: String { "\(supportDir)/top-charts.json" }
    private var statePath: String { "\(supportDir)/last-genre.json" }
    private var resumeFlagPath: String { "\(supportDir)/resume-on-login" }

    private var nowPlayingCLI: String {
        for candidate in ["/opt/homebrew/bin/nowplaying-cli", "/usr/local/bin/nowplaying-cli", "/opt/local/bin/nowplaying-cli"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "nowplaying-cli"
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "♫"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.contentViewController = playerVC
        popover.behavior = .transient
        popover.animates = false
        playerVC.onTransport = { [weak self] command in
            self?.runProcess([self?.nowPlayingCLI ?? "nowplaying-cli", command])
        }
        playerVC.onShuffle = { [weak self] in self?.shuffle() }

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
                  let firstVideoId = entry["firstVideoId"] as? String else { return nil }
            let videoIds = (entry["videoIds"] as? [String]) ?? [firstVideoId]
            return Genre(name: name, playlistId: playlistId, firstVideoId: firstVideoId, videoIds: videoIds)
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let m = NSMenu()
        m.delegate = self

        let header = NSMenuItem(title: "FreeTube", action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)

        let nowPlaying = NSMenuItem(title: "Now Playing: —", action: nil, keyEquivalent: "")
        nowPlaying.isEnabled = false
        nowPlayingItem = nowPlaying
        m.addItem(nowPlaying)

        m.addItem(.separator())

        m.addItem(makeItem("Play / Pause", #selector(playPause)))
        m.addItem(makeItem("Next Track", #selector(nextTrack)))
        m.addItem(makeItem("Previous Track", #selector(previousTrack)))
        m.addItem(makeItem("Shuffle All Genres", #selector(shuffle)))

        m.addItem(.separator())

        if genres.isEmpty {
            let empty = NSMenuItem(title: "No Top Charts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            m.addItem(empty)
        } else {
            let genresMenu = NSMenu(title: "Genres")
            for genre in genres {
                let play = NSMenuItem(title: genre.name, action: #selector(playGenre(_:)), keyEquivalent: "")
                play.target = self
                play.representedObject = [genre.playlistId, genre.firstVideoId]
                genresMenu.addItem(play)

                let shuf = NSMenuItem(title: "  Shuffle \(genre.name)", action: #selector(shuffleGenre(_:)), keyEquivalent: "")
                shuf.target = self
                shuf.representedObject = ["playlistId": genre.playlistId, "videoIds": genre.videoIds]
                genresMenu.addItem(shuf)
            }
            let genresItem = NSMenuItem(title: "Genres", action: nil, keyEquivalent: "")
            genresItem.submenu = genresMenu
            m.addItem(genresItem)
        }

        m.addItem(.separator())

        resumeItem = NSMenuItem(title: "Resume last genre on login", action: #selector(toggleResume), keyEquivalent: "")
        resumeItem.target = self
        resumeItem.state = FileManager.default.fileExists(atPath: resumeFlagPath) ? .on : .off
        m.addItem(resumeItem)

        m.addItem(makeItem("Open FreeTube", #selector(openFreeTube)))
        m.addItem(makeItem("Refresh Top Charts", #selector(refreshCharts)))
        m.addItem(makeItem("Reload Genres", #selector(refreshGenres)))

        m.addItem(.separator())

        let quit = NSMenuItem(title: "Quit FreeTube Bar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        menu = m
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let title = runProcess([nowPlayingCLI, "get", "title"])
        nowPlayingItem?.title = title.isEmpty ? "Now Playing: —" : "Now Playing: \(title)"
    }

    // MARK: - Status item click

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            playerVC.setActive(false)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            playerVC.setActive(true)
        }
    }

    // MARK: - Actions

    @objc private func playPause() { _ = runProcess([nowPlayingCLI, "togglePlayPause"]) }
    @objc private func nextTrack() { _ = runProcess([nowPlayingCLI, "next"]) }
    @objc private func previousTrack() { _ = runProcess([nowPlayingCLI, "previous"]) }

    @objc private func openFreeTube() { _ = runProcess(["/usr/bin/open", "-a", "FreeTube"]) }

    @objc private func playGenre(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        let url = "https://www.youtube.com/watch?v=\(pair[1])&list=\(pair[0])"
        recordLast(playlistId: pair[0], videoId: pair[1])
        _ = runProcess(["/usr/bin/open", "-a", "FreeTube", url])
    }

    @objc private func shuffleGenre(_ sender: NSMenuItem) {
        guard let dict = sender.representedObject as? [String: Any],
              let playlistId = dict["playlistId"] as? String,
              let videoIds = dict["videoIds"] as? [String],
              let videoId = videoIds.randomElement() else { return }
        let url = "https://www.youtube.com/watch?v=\(videoId)&list=\(playlistId)"
        recordLast(playlistId: playlistId, videoId: videoId)
        _ = runProcess(["/usr/bin/open", "-a", "FreeTube", url])
    }

    @objc private func shuffle() {
        // Prefer the cross-genre Radio Mix when available.
        if let radio = genres.first(where: { $0.name == "Radio Mix" }),
           let videoId = radio.videoIds.randomElement() {
            let url = "https://www.youtube.com/watch?v=\(videoId)&list=\(radio.playlistId)"
            recordLast(playlistId: radio.playlistId, videoId: videoId)
            _ = runProcess(["/usr/bin/open", "-a", "FreeTube", url])
            return
        }
        guard let genre = genres.randomElement() else { return }
        let videoId = genre.videoIds.randomElement() ?? genre.firstVideoId
        let url = "https://www.youtube.com/watch?v=\(videoId)&list=\(genre.playlistId)"
        recordLast(playlistId: genre.playlistId, videoId: videoId)
        _ = runProcess(["/usr/bin/open", "-a", "FreeTube", url])
    }

    @objc private func toggleResume() {
        if FileManager.default.fileExists(atPath: resumeFlagPath) {
            try? FileManager.default.removeItem(atPath: resumeFlagPath)
            resumeItem.state = .off
        } else {
            try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: resumeFlagPath, contents: Data(), attributes: nil)
            resumeItem.state = .on
        }
    }

    @objc private func refreshGenres() {
        loadManifest()
        rebuildMenu()
    }

    @objc private func refreshCharts() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        _ = runProcess(["/bin/bash", "\(home)/Library/Scripts/update-top-music.sh", "--force"])
        loadManifest()
        rebuildMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - State

    private func recordLast(playlistId: String, videoId: String) {
        let name = genres.first(where: { $0.playlistId == playlistId })?.name ?? playlistId
        let dict: [String: String] = ["name": name, "playlistId": playlistId, "videoId": videoId]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return }
        try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
    }

    // MARK: - Process

    @discardableResult
    private func runProcess(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() }
        catch { return "" }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - Player popover

final class PlayerViewController: NSViewController {
    var onTransport: ((String) -> Void)?
    var onShuffle: (() -> Void)?

    private let artwork = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "—")
    private let artistLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "0:00 / 0:00")
    private let progress = NSProgressIndicator()
    private var timer: Timer?
    private var lastArtwork: String = ""

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 230))

        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 8
        artwork.layer?.masksToBounds = true
        view.addSubview(artwork)

        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        view.addSubview(titleLabel)

        artistLabel.font = NSFont.systemFont(ofSize: 12)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.alignment = .center
        artistLabel.lineBreakMode = .byTruncatingTail
        view.addSubview(artistLabel)

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        view.addSubview(progress)

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .center
        view.addSubview(timeLabel)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 18
        row.addArrangedSubview(makeButton("backward.fill", #selector(previous)))
        row.addArrangedSubview(makeButton("play.fill", #selector(playPause)))
        row.addArrangedSubview(makeButton("forward.fill", #selector(next)))
        row.addArrangedSubview(makeButton("shuffle", #selector(shuffle)))
        view.addSubview(row)

        [artwork, titleLabel, artistLabel, progress, timeLabel, row].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            artwork.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            artwork.widthAnchor.constraint(equalToConstant: 96),
            artwork.heightAnchor.constraint(equalToConstant: 96),

            titleLabel.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            artistLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            artistLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            artistLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            progress.topAnchor.constraint(equalTo: artistLabel.bottomAnchor, constant: 8),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            timeLabel.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 4),
            timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            row.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 8),
            row.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            row.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
        ])

        self.view = view
        preferredContentSize = view.fittingSize
    }

    private func makeButton(_ symbol: String, _ action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        return button
    }

    func setActive(_ active: Bool) {
        if active {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func refresh() {
        let json = runProcess(["nowplaying-cli", "get", "--json",
                               "title", "artist", "duration", "elapsedTime", "playbackRate", "artworkData"])
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            titleLabel.stringValue = "Nothing playing"
            artistLabel.stringValue = "Pick a genre from the ♫ menu"
            return
        }

        let title = obj["title"] as? String ?? ""
        let artist = obj["artist"] as? String ?? ""
        titleLabel.stringValue = title.isEmpty ? "Nothing playing" : title
        artistLabel.stringValue = artist

        let duration = (obj["duration"] as? NSNumber)?.doubleValue ?? 0
        let elapsed = (obj["elapsedTime"] as? NSNumber)?.doubleValue ?? 0
        timeLabel.stringValue = "\(fmt(elapsed)) / \(fmt(duration))"
        progress.doubleValue = duration > 0 ? elapsed / duration : 0

        if let b64 = obj["artworkData"] as? String, b64 != lastArtwork,
           let imgData = Data(base64Encoded: b64), let image = NSImage(data: imgData) {
            artwork.image = image
            lastArtwork = b64
        }
    }

    private func fmt(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @objc private func playPause() { onTransport?("togglePlayPause") }
    @objc private func next() { onTransport?("next") }
    @objc private func previous() { onTransport?("previous") }
    @objc private func shuffle() { onShuffle?() }

    private func runProcess(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() }
        catch { return "" }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
