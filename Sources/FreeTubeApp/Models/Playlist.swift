import Foundation

struct Playlist: Identifiable, Codable, Equatable, Hashable {
    var id: String { playlistItemId ?? UUID().uuidString }
    let playlistItemId: String?
    let playlistName: String
    var protected: Bool = false
    let description: String?
    var videos: [Track] = []
    let createdAt: Int64?
    var lastUpdatedAt: Int64?
    var lastPlayedAt: Int64?

    init(playlistItemId: String? = nil, playlistName: String, protected: Bool = false,
         description: String? = nil, videos: [Track] = [], createdAt: Int64? = nil,
         lastUpdatedAt: Int64? = nil, lastPlayedAt: Int64? = nil) {
        self.playlistItemId = playlistItemId
        self.playlistName = playlistName
        self.protected = protected
        self.description = description
        self.videos = videos
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.lastPlayedAt = lastPlayedAt
    }

    var trackCount: Int { videos.count }
}
