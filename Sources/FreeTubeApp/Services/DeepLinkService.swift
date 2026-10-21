import Foundation
import AppKit

/// Opens videos, channels and playlists inside FreeTube via its
/// `freetube://` URL scheme — the app can drive FreeTube directly,
/// not just shell out to it.
final class DeepLinkService {
    static let shared = DeepLinkService()

    func openVideo(_ videoId: String) {
        guard !videoId.isEmpty else { return }
        open("freetube://https://www.youtube.com/watch?v=\(videoId)")
    }

    func openChannel(_ channelId: String) {
        guard !channelId.isEmpty else { return }
        open("freetube://https://www.youtube.com/channel/\(channelId)")
    }

    func openPlaylist(playlistId: String, firstVideoId: String) {
        guard !playlistId.isEmpty else { return }
        open("freetube://https://www.youtube.com/playlist?list=\(playlistId)")
        _ = firstVideoId // FreeTube handles playlist context itself
    }

    func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The raw URL for display/debugging purposes.
    static func videoURL(for videoId: String) -> String {
        "freetube://https://www.youtube.com/watch?v=\(videoId)"
    }
}
