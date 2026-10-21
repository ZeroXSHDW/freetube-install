import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var viewModel = NowPlayingViewModel.shared
    @ObservedObject var sponsor = SponsorBlockService.shared
    @ObservedObject var license = LicenseService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Now Playing")
                        .font(.title2)
                        .fontWeight(.bold)
                    if license.isPro {
                        Text("PRO")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                Text("FreeTube plays; this app switches tracks, hearts them, skips sponsors and keeps the queue endless.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            VStack(spacing: 18) {
                // Artwork
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 140, height: 140)
                    if let artwork = viewModel.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 140, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 4) {
                    Text(viewModel.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(viewModel.artist.isEmpty ? "— via FreeTube" : viewModel.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // SponsorBlock toast
                if let toast = sponsor.skipToast {
                    Label(toast, systemImage: "forward.end.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }

                // Progress
                VStack(spacing: 4) {
                    HStack {
                        Text(viewModel.currentTime)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.duration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { viewModel.progress },
                        set: { newValue in
                            viewModel.progress = newValue
                            viewModel.seek(to: newValue * viewModel.durationSeconds)
                        }), in: 0...1)
                }

                // Transport
                HStack(spacing: 18) {
                    Button(action: { viewModel.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.playPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }

                // Pin row + endless toggle
                HStack(spacing: 16) {
                    Button {
                        viewModel.toggleFavorite()
                    } label: {
                        Label("Favorite", systemImage: viewModel.isFavorite ? "heart.fill" : "heart")
                            .symbolRenderingMode(viewModel.isFavorite ? .multicolor : .hierarchical)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.toggleWatchLater()
                    } label: {
                        Label("Later", systemImage: viewModel.isWatchLater ? "clock.fill" : "clock")
                    }
                    .buttonStyle(.bordered)

                    Toggle(isOn: $viewModel.endlessMode) {
                        Label("Endless queue", systemImage: "infinity")
                    }
                    .toggleStyle(.button)

                    Spacer()
                }

                // Playing state
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isPlaying ? "circle.fill" : "circle")
                        .foregroundStyle(viewModel.isPlaying ? .green : .gray)
                        .font(.caption2)
                    Text(viewModel.isPlaying ? "Playing in FreeTube" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !viewModel.nowPlayingCLIInstalled {
                        Text("· install nowplaying-cli for full controls")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }

                // Up next
                if !viewModel.queue.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.currentGenre.map { "Up next — Top Charts \($0.name)" } ?? "Queue")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(Array(viewModel.queue.enumerated().filter { $0.offset > viewModel.queueIndex }.prefix(4)), id: \.element.id) { pair in
                                Button {
                                    viewModel.playIndex(pair.offset)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        AsyncImage(url: pair.element.thumbnailURL) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Image(systemName: "music.note")
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(width: 64, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        Text(pair.element.title)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 64)
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear { viewModel.startMonitoring() }
        .onDisappear { viewModel.stopMonitoring() }
    }
}
