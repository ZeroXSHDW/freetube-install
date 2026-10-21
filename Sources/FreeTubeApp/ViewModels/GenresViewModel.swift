import Foundation
import SwiftUI

@MainActor
final class GenresViewModel: ObservableObject {
    let playlistService = PlaylistService.shared

    @Published var selectedGenre: Genre?
    @Published var showingPlayAlert = false
    @Published var playURL: URL?

    func playGenre(_ genre: Genre) {
        selectedGenre = genre
        if let url = URL(string: "https://www.youtube.com/watch?v=\(genre.firstVideoId)&list=\(genre.playlistId)") {
            playURL = url
            showingPlayAlert = true
        }
    }

    func playRadioMix() {
        guard let radio = Genre.allGenres.first(where: { $0.name == "Radio Mix" }) else { return }
        playGenre(radio)
    }

    var genreCount: Int {
        Genre.allGenres.count
    }
}
