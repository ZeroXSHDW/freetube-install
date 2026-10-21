import Foundation

struct Track: Identifiable, Codable, Equatable, Hashable {
    var id: String { videoId }
    let videoId: String
    let title: String
    let author: String
    let authorId: String?
    var lengthSeconds: Int
    let published: Int64?
    let timeAdded: Int64?
    let playlistItemId: String?
    var type: String

    init(videoId: String, title: String, author: String = "", authorId: String? = nil,
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

    /// Tolerant decoding: FreeTubeBar's favorites.json and FreeTube DB entries
    /// sometimes omit fields, so treat everything as optional with defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoId = (try? container.decodeIfPresent(String.self, forKey: .videoId)) ?? ""
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? "Unknown title"
        author = (try? container.decodeIfPresent(String.self, forKey: .author)) ?? ""
        authorId = try? container.decodeIfPresent(String.self, forKey: .authorId)
        lengthSeconds = (try? container.decodeIfPresent(Int.self, forKey: .lengthSeconds)) ?? 0
        published = try? container.decodeIfPresent(Int64.self, forKey: .published)
        timeAdded = try? container.decodeIfPresent(Int64.self, forKey: .timeAdded)
        playlistItemId = try? container.decodeIfPresent(String.self, forKey: .playlistItemId)
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "video"
    }

    enum CodingKeys: String, CodingKey {
        case videoId, title, author, authorId, lengthSeconds
        case published, timeAdded, playlistItemId, type
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(videoId, forKey: .videoId)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        if let authorId { try container.encode(authorId, forKey: .authorId) }
        try container.encode(lengthSeconds, forKey: .lengthSeconds)
        if let published { try container.encode(published, forKey: .published) }
        if let timeAdded { try container.encode(timeAdded, forKey: .timeAdded) }
        if let playlistItemId { try container.encode(playlistItemId, forKey: .playlistItemId) }
        try container.encode(type, forKey: .type)
    }

    var durationFormatted: String {
        let total = max(0, lengthSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    var youtubeURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")
    }

    var thumbnailURL: URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
    }
}
