# FreeTube macOS installer

Installs the official [FreeTube](https://freetubeapp.io/) macOS release with SHA-256 verification, restores a configuration snapshot, and registers a checksum-verified auto-updater. Companion to [freetube-configs](https://github.com/ZeroXSHDW/freetube-configs-main), which holds the portable settings, playlists, and profiles.

## Why this exists

FreeTube's macOS builds are **ad-hoc signed, not notarized**, so the Homebrew cask is disabled and Gatekeeper blocks the app by default. This installer:

1. Downloads the release DMG from GitHub and verifies its SHA-256 digest (the same value published by GitHub and by the Homebrew cask).
2. Verifies the app bundle's code signature after install.
3. Removes the quarantine attribute so macOS allows it to run.
4. Optionally restores a config snapshot from `freetube-configs`.
5. Installs a LaunchAgent that keeps FreeTube up to date at login and every 6 hours.

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
scripts/freetube-autoupdate.sh         Checksum-verified auto-updater
scripts/freetube-doctor.sh             Diagnostics
launchd/                               LaunchAgent template
docs/
```

## License

MIT — see [LICENSE](LICENSE).
