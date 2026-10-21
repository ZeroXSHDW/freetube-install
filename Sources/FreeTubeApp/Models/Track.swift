import Foundation

struct Track: Identifiable, Codable, Equatable, Hashable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let author: String
    let authorId: String?
    let lengthSeconds: Int
    let published: Int64?
    let timeAdded: Int64?
    let playlistItemId: String?
    var type: String = "video"

    init(videoId: String, title: String, author: String, authorId: String? = nil,
         lengthSeconds: Int = 0, published: Int64? = nil, timeAdded: Int64? = nil,
         playlistItemId: String? = nil, type: String = "video") {
        self.videoId = videoId
        self.title = title
        self.author = author
        self.authorId = authorId
        self.lengthSeconds = lengthSeconds
        self.published = published
        self.timeAdded = timeAdded
        self.playlistItemId = playlistItemId
        self.type = type
    }

    var durationFormatted: String {
        let total = max(0, lengthSeconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")
    }
}
