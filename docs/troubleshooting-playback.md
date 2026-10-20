# Troubleshooting playback

FreeTube is configured for the most resilient combination available:

- **Local API** preferred (direct YouTube extraction), **Invidious fallback** enabled.
- **RSS feeds** for subscriptions.
- **DASH + 720p** adaptive streams.

This is best-effort. FreeTube cannot bypass DRM, deleted/private videos,
regional licensing, or an ISP that blocks YouTube entirely.

## Quick reference

| Symptom | Fix |
| --- | --- |
| "Sign in to confirm you're not a bot" / "IP block" | Fallback should use Invidious; if it also fails, use a VPN/proxy |
| "Video unavailable" / "Private video" | Remove the entry from the playlist |
| "This live stream recording is not available" | Remove the entry |
| DRM protected | Unsupported by FreeTube |
| Fallback toast shows every time | Pin a working instance in Settings → General → Invidious Instance |
| Stalls on a specific video | Press play again (re-extracts) or lower quality to 480p |

## Steps

1. Press play again — expired stream URLs are re-extracted.
2. Switch backend: **Settings → General → Preferred API Backend** (Local ↔ Invidious). Keep fallback on.
3. Choose another Invidious instance: **Settings → General → Invidious Instance**. Public instances come and go.
4. Use a VPN, or FreeTube's proxy: **Settings → Proxy Settings → Enable Tor / Proxy**. The companion repo's `scripts/set-proxy.sh` can toggle this from the CLI.
5. Update FreeTube: run `./install.sh` (or the auto-updater will do it at login / every 6 hours).

## Diagnostics

```bash
./scripts/freetube-doctor.sh   # install + network + Now Playing checks
./verify.sh                    # signature, updater, config checks
```

## Known limitations

- Public Invidious instances are frequently overloaded or blocked; a working
  instance today can fail tomorrow.
- FreeTube does not rotate through multiple Invidious instances automatically.
  If the fallback instance is dead, pick another or restart FreeTube to randomize.
- Proxying video streams is slow; prefer a VPN or a direct connection.
- Unavailable videos embedded in a playlist interrupt autoplay when reached.
  Remove them from the playlist.
