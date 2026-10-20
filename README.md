# FreeTube macOS installer

Installs the official [FreeTube](https://freetubeapp.io/) macOS release with SHA-256 verification, restores a configuration snapshot, and registers a checksum-verified auto-updater. Companion to [freetube-configs](https://github.com/ZeroXSHDW/freetube-configs-main), which holds the portable settings, playlists, and profiles.

## Why this exists

FreeTube's macOS builds are **ad-hoc signed, not notarized**, so the Homebrew cask is disabled and Gatekeeper blocks the app by default. This installer:

1. Downloads the release DMG from GitHub and verifies its SHA-256 digest (the same value published by GitHub and by the Homebrew cask).
2. Verifies the app bundle's code signature after install.
3. Removes the quarantine attribute so macOS allows it to run.
4. Optionally restores a config snapshot from `freetube-configs`.
5. Installs three LaunchAgents:
   - **FreeTube auto-update** (login + every 6 h).
   - **Top Charts refresh** (login + every 6 h) — keeps 18 genre playlists updated with the most popular music in each genre.
   - **FreeTubeBar** — a native menu-bar app (♫ icon) with Now Playing controls and a click-to-play genre menu.

> The release DMG is **not** committed here (GitHub rejects files over 100 MB). The installer always downloads the current release and verifies its digest.

## Requirements

- macOS 12 or newer, Apple Silicon (`arm64`) or Intel (`x64`)
- `curl`, `python3`, and Xcode Command Line Tools (`hdiutil`, `codesign`, `xattr`, `shasum` are included with the CLT)

## Install

```bash
git clone https://github.com/ZeroXSHDW/freetube-configs-main.git
git clone https://github.com/ZeroXSHDW/freetube-install.git
cd freetube-install
./install.sh
```

The default install:

- Places `FreeTube.app` in `~/Applications` (no admin password needed).
- Restores config from `../freetube-configs-main` if present.
- Installs the auto-updater (login + every 6 hours).
- Launches FreeTube.

Options:

```bash
./install.sh --version 0.25.3            # pin a version
./install.sh --system                    # install to /Applications (needs sudo; no auto-update)
./install.sh --no-config                 # skip config restore
./install.sh --config-dir /path/to/config
./install.sh --menu-bar-now-playing      # show Now Playing in the menu bar
./install.sh --no-launch
```

## Update

Updates are automatic for per-user installs. To force an immediate check:

```bash
launchctl kickstart -k gui/$(id -u)/local.freetube.autoupdate
# or run it directly:
~/Library/Scripts/FreeTubeAutoUpdate.sh
```

Logs: `~/Library/Logs/FreeTubeAutoUpdate.log`. The updater skips while FreeTube is running and never replaces the app without verifying the digest and signature.

## Top Charts auto-update

FreeTube has no built-in "auto-populate trending" feature, so this repo adds one. It:

1. Pulls the iTunes Top 100 charts for **18 genres** (Pop, Hip-Hop/Rap, Rock, Country, R&B/Soul, Electronic, Dance, Alternative, Latin, Reggae, Jazz, Classical, Blues, Singer/Songwriter, World, Soundtrack, Russian Rap, Russian Pop).
2. Resolves each song to its official YouTube video via Invidious.
3. Drops removed videos and writes one FreeTube playlist per genre (`Top Charts — <Genre>`), plus a manifest the menu bar app reads.

It runs at login and every 6 hours, but only when FreeTube is **closed** (editing the database under a running app would be overwritten). To refresh now:

```bash
~/Library/Scripts/update-top-music.sh --force   # quits, refreshes, relaunches
~/Library/Scripts/update-top-music.sh --dry-run # preview without changing anything
```

Logs: `~/Library/Logs/FreeTubeTopMusic.log`.

## Menu bar app (FreeTubeBar)

A native Swift menu-bar item (♫) compiled at install time:

- **Left-click** the ♫ for a Now Playing **popover**: album art, title, artist, a progress bar, and Play/Pause / Previous / Next / Shuffle.
- **Right-click** for the menu:
  - Now Playing title, Play/Pause, Next, Previous, **Shuffle All Genres**.
  - **Genres** — click to play a genre, or **Shuffle `<genre>`** to start it at a random track.
  - **Resume last genre on login** (toggle) — remembers what you were playing and auto-resumes it at login.
  - Open FreeTube, Refresh Genres, Quit.

It runs at login and stays in the menu bar. To play a genre from the terminal:

```bash
~/Library/Scripts/play-genre.sh "Hip-Hop/Rap"     # or any genre name
```

Source: `bar/FreeTubeBar.swift` (compiled with `swiftc`, requires Xcode Command Line Tools).

### Resume on login

When **Resume last genre on login** is on, the last genre you played is recorded to `~/Library/Application Support/FreeTube/last-genre.json`, and a login LaunchAgent re-opens it in FreeTube a few seconds after you sign in. Turn the toggle off in the ♫ menu to disable it.

## Verify / troubleshoot

```bash
./verify.sh                      # app, signature, updater, config sanity
./scripts/freetube-doctor.sh     # install + network + Now Playing diagnostics
```

## Uninstall

```bash
./uninstall.sh           # remove app and updater, keep your data
./uninstall.sh --purge   # also move ~/Library/Application Support/FreeTube aside
```

## Docs

- [docs/media-keys-and-now-playing.md](docs/media-keys-and-now-playing.md)
- [docs/troubleshooting-playback.md](docs/troubleshooting-playback.md)

## Layout

```text
install.sh                             Main installer
uninstall.sh
verify.sh
bar/FreeTubeBar.swift                  Menu bar app source
scripts/freetube-autoupdate.sh         Checksum-verified auto-updater
scripts/update-top-music.py            Top Charts playlist generator (18 genres)
scripts/update-top-music.sh            Top Charts wrapper
scripts/play-genre.sh                  Play a genre from the CLI
scripts/resume-last.sh                 Resume last genre on login
scripts/freetube-doctor.sh             Diagnostics
launchd/                               LaunchAgent templates
docs/
```

## License

MIT — see [LICENSE](LICENSE).
