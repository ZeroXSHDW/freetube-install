import SwiftUI

struct GenresView: View {
    @ObservedObject var viewModel: GenresViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top Charts Genres")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Play any of the 18 auto-refreshed Top Charts genres. Click a genre to open it in FreeTube.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            List(Genre.allGenres) { genre in
                Button(action: {
                    viewModel.playGenre(genre)
                }) {
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        Text(genre.name)
                            .font(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack {
                Button(action: {
                    viewModel.playRadioMix()
                }) {
                    Label("Play Cross-Genre Radio Mix", systemImage: "radio")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 450, height: 550)
        .alert("Open in FreeTube", isPresented: $viewModel.showingPlayAlert) {
            Button("Open") {
                if let url = viewModel.playURL {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let genre = viewModel.selectedGenre {
                Text("Open \"\(genre.name)\" in FreeTube?")
            } else {
                Text("Open genre in FreeTube?")
            }
        }
    }
}
