import SwiftUI
import AppKit

/// Compact Now Playing + quick genre launcher shown in the menu bar popover.
/// Drives FreeTube through `freetube://` deep links and the system media controls.
struct MenuBarPopoverView: View {
    @ObservedObject var nowPlaying = NowPlayingViewModel.shared
    @ObservedObject var playlist = PlaylistService.shared
    @ObservedObject var license = LicenseService.shared

    private var quickGenres: [Genre] {
        Array(Genre.allGenres.filter { $0.name != "Radio Mix" }.prefix(6))
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 46, height: 46)
                    if let artwork = nowPlaying.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(nowPlaying.artist.isEmpty ? "FreeTube" : nowPlaying.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if license.isPro {
                    Text("PRO")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }

            // Progress
            VStack(spacing: 2) {
                ProgressView(value: nowPlaying.progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text(nowPlaying.currentTime)
                    Spacer()
                    Text(nowPlaying.duration)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            // Transport
            HStack(spacing: 14) {
                Button { nowPlaying.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)

                Button { nowPlaying.playPause() } label: {
                    Image(systemName: nowPlaying.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Button { nowPlaying.next() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
            }

            // Pin / skip row
            HStack(spacing: 10) {
                Button { nowPlaying.toggleFavorite() } label: {
                    Image(systemName: nowPlaying.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(nowPlaying.isFavorite ? .red : .secondary)
                }
                .buttonStyle(.plain)

                Button { nowPlaying.toggleWatchLater() } label: {
                    Image(systemName: nowPlaying.isWatchLater ? "clock.fill" : "clock")
                        .foregroundStyle(nowPlaying.isWatchLater ? .blue : .secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if let toast = SponsorBlockService.shared.skipToast {
                    Text(toast)
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }

            Divider()

            // Quick genre launcher
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick play")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(quickGenres) { genre in
                        Button(genre.name) {
                            _ = nowPlaying.tryLoadQueue(for: genre)
                            nowPlaying.playGenre(genre)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }

            Divider()

            HStack {
                Button("Open full app") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("FreeTube") {
                    InstallationService.shared.openFreeTube()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            playlist.loadPlaylists()
            nowPlaying.startMonitoring()
        }
    }
}
