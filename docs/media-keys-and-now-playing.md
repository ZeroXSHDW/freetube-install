# Media keys and Now Playing (macOS)

FreeTube implements the W3C Media Session API. On macOS that means the system
**Now Playing** service drives FreeTube exactly like Apple Music:

- **Keyboard Play/Pause** (F8 / fn+F8) → pause/play
- **Keyboard Next** (F9 / fn+F9) → next playlist item
- **Keyboard Previous** (F7 / fn+F7) → previous playlist item
- **Control Center** Now Playing → title, channel, artwork, duration, controls
- **Menu bar** Now Playing item (optional; see below)
- **AirPods / Bluetooth** → same MediaRemote path

Next/Previous work only when playback started **from a playlist**. On the last
track, Next does nothing rather than wrapping around.

## Verify

```bash
brew install nowplaying-cli
nowplaying-cli get title artist playbackRate
nowplaying-cli togglePlayPause   # same as the keyboard play/pause key
nowplaying-cli next
nowplaying-cli previous
```

If `nowplaying-cli get title` is empty, no app currently owns the Now Playing
session. Start FreeTube playback and try again.

## Menu bar Now Playing item

1. **System Settings → Control Center**
2. Scroll to **Now Playing**
3. Enable **Show in Menu Bar**

Or set the preference directly (then restart Control Center):

```bash
defaults -currentHost write com.apple.controlcenter "NSStatusItem Visible NowPlaying" -bool true
killall ControlCenter
```

The installer can do this for you with `./install.sh --menu-bar-now-playing`.

## Background listening

- **Minimize** (`Cmd+M`) or **hide** (`Cmd+H`) — audio keeps playing.
- Do **not** close the window; that destroys the player. Quitting stops playback.
- Autoplay runs for up to **12 hours** without interaction; a click or key press resets it.
- System sleep stops playback; display sleep does not.

## If media keys control another app

macOS routes media keys to the most recent Now Playing owner. Start playback in
FreeTube again (or pause/quit the other media app) and the keys return to FreeTube.
