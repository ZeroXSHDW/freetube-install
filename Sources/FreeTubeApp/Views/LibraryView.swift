import SwiftUI

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Library")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Favorites, Watch Later, history and subscriptions — straight from FreeTube's own databases. Everything stays in sync with FreeTubeBar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Picker("Section", selection: $viewModel.section) {
                ForEach(LibraryViewModel.Section.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if let status = viewModel.statusLine {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }

            Divider().padding(.top, 10)

            content
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.exportAll()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear { viewModel.reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.section {
        case .favorites:
            trackList(viewModel.library.favorites, emptyText: "No favorites yet — tap ♥ in Now Playing to heart the current track.")
        case .watchLater:
            trackList(viewModel.library.watchLater, emptyText: "No watch-later tracks yet — tap 🕓 in Now Playing.")
        case .history:
            historyList
        case .subscriptions:
            subscriptionsList
        }
    }

    private func trackList(_ tracks: [Track], emptyText: String) -> some View {
        Group {
            if tracks.isEmpty {
                EmptyStateView(text: emptyText)
            } else {
                List(tracks) { track in
                    TrackRow(track: track,
                             favorite: viewModel.library.isFavorite(track.videoId),
                             watchLater: viewModel.library.isWatchLater(track.videoId),
                             onOpen: { viewModel.open(track) },
                             onFavorite: { viewModel.toggleFavorite(track) },
                             onWatchLater: { viewModel.toggleWatchLater(track) })
                }
            }
        }
    }

    private var historyList: some View {
        Group {
            if viewModel.data.history.isEmpty {
                EmptyStateView(text: "FreeTube history is empty (or FreeTube hasn't been launched yet).")
            } else {
                List(viewModel.data.recentUniqueHistory(limit: 150)) { track in
                    TrackRow(track: track,
                             favorite: viewModel.library.isFavorite(track.videoId),
                             watchLater: viewModel.library.isWatchLater(track.videoId),
                             onOpen: { viewModel.open(track) },
                             onFavorite: { viewModel.toggleFavorite(track) },
                             onWatchLater: { viewModel.toggleWatchLater(track) },
                             deletionLabel: "Drop",
                             onDelete: { viewModel.removeFromHistory(track) })
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button("Clean history older than 30 days") {
                            viewModel.clearHistory(olderThanDays: 30)
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Text("FreeTube must be closed for cleanup")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
    }

    private var subscriptionsList: some View {
        Group {
            if viewModel.data.subscriptions.isEmpty {
                EmptyStateView(text: "No subscriptions found. Subscribe to channels inside FreeTube first.")
            } else {
                List(viewModel.data.subscriptions) { channel in
                    Button {
                        viewModel.openChannel(channel)
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.orange)
                            Text(channel.name)
                                .font(.body)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Reusable track row with deep-link open, ♥ and 🕓 actions.
struct TrackRow: View {
    let track: Track
    let favorite: Bool
    let watchLater: Bool
    let onOpen: () -> Void
    let onFavorite: () -> Void
    let onWatchLater: () -> Void
    var deletionLabel: String? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    AsyncImage(url: track.thumbnailURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 44, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.body)
                            .lineLimit(1)
                        Text(track.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(track.durationFormatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                onFavorite()
            } label: {
                Image(systemName: favorite ? "heart.fill" : "heart")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(favorite ? .red : .secondary)

            Button {
                onWatchLater()
            } label: {
                Image(systemName: watchLater ? "clock.fill" : "clock")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(watchLater ? .blue : .secondary)

            if let deletionLabel, let onDelete {
                Button(deletionLabel, action: onDelete)
                    .buttonStyle(.link)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }
}

struct EmptyStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
