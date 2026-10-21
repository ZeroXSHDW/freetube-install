import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var viewModel: NowPlayingViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Now Playing")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Media key controls and track information from FreeTube.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            // Main content
            VStack(spacing: 20) {
                // Artwork
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 120, height: 120)
                    if let artwork = viewModel.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
                }

                // Title / Artist
                VStack(spacing: 4) {
                    Text(viewModel.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    Text(viewModel.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Progress
                VStack(spacing: 4) {
                    HStack {
                        Text(viewModel.currentTime)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(viewModel.duration)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.progress, in: 0...1) { editing in
                        if !editing {
                            let seconds = viewModel.progress * max(1, Double(viewModel.duration.replacingOccurrences(of: ":", with: "").split(separator: ":").count > 0 ? 0 : 0))
                            // Use seconds from currentTime/duration parsing
                            let parts = viewModel.currentTime.split(separator: ":")
                            if parts.count == 2,
                               let mins = Int(parts[0]), let secs = Int(parts[1]) {
                                let totalSeconds = mins * 60 + secs
                                viewModel.seek(to: Double(totalSeconds))
                            }
                        }
                    }
                }

                // Transport controls
                HStack(spacing: 16) {
                    Button(action: { viewModel.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)

                    Button(action: { viewModel.playPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Circle())

                    Button(action: { viewModel.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }

                // Status
                HStack(spacing: 12) {
                    Image(systemName: viewModel.isPlaying ? "circle.fill" : "circle")
                        .foregroundStyle(viewModel.isPlaying ? .green : .gray)
                        .font(.caption)
                    Text(viewModel.isPlaying ? "Playing" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Controls bar
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.startMonitoring()
                }) {
                    Label("Start Monitoring", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    viewModel.stopMonitoring()
                }) {
                    Label("Stop", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button("Close") {
                    // Just close the window/sheet
                }
                .keyboardShortcut(.cancelAction)

                Spacer()
            }
            .padding()
        }
        .frame(width: 500, height: 550)
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
}
