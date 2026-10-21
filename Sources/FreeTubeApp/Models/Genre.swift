import Foundation

struct Genre: Identifiable, Codable, Equatable, Hashable {
    var id: String { playlistId }
    let name: String
    let playlistId: String
    let firstVideoId: String
    var videoIds: [String] = []

    init(name: String, playlistId: String, firstVideoId: String, videoIds: [String] = []) {
        self.name = name
        self.playlistId = playlistId
        self.firstVideoId = firstVideoId
        self.videoIds = videoIds
    }

    static let allGenres: [Genre] = [
        Genre(name: "Pop", playlistId: "ft-playlist--f57ffd84-a5ea-45d5-8129-b48e24f4d2dc", firstVideoId: ""),
        Genre(name: "Hip-Hop/Rap", playlistId: "ft-playlist--b4395627-d6b2-4d65-a296-1836e7aa6da9", firstVideoId: ""),
        Genre(name: "Rock", playlistId: "ft-playlist--7a04651f-260f-438d-ae53-0dd4e9d15f74", firstVideoId: ""),
        Genre(name: "Country", playlistId: "ft-playlist--04965f80-08ba-41f4-94ca-dbad384ec476", firstVideoId: ""),
        Genre(name: "R&B/Soul", playlistId: "ft-playlist--19410a60-d8d8-4b50-8169-dc46547f766f", firstVideoId: ""),
        Genre(name: "Electronic", playlistId: "ft-playlist--6d891e90-99a0-4a2f-8a23-b8d711d047f7", firstVideoId: ""),
        Genre(name: "Dance", playlistId: "ft-playlist--6369c292-8f69-494c-a32f-de68088c8135", firstVideoId: ""),
        Genre(name: "Alternative", playlistId: "ft-playlist--fb4aa356-4156-4804-b17c-156ec57e986c", firstVideoId: ""),
        Genre(name: "Latin", playlistId: "ft-playlist--53ffc935-95bf-4c6c-8925-e5b61857eb4a", firstVideoId: ""),
        Genre(name: "Reggae", playlistId: "ft-playlist--0d49ae5b-fd6f-41cd-a4dc-88aa88d5e88c", firstVideoId: ""),
        Genre(name: "Jazz", playlistId: "ft-playlist--6ee19f2d-4768-42f2-a244-5fc627ea0ec9", firstVideoId: ""),
        Genre(name: "Classical", playlistId: "ft-playlist--b52fb133-ce7b-49b3-a540-fd6c885eaab0", firstVideoId: ""),
        Genre(name: "Blues", playlistId: "ft-playlist--b607d848-2f2f-4bee-afb1-b0046c41826c", firstVideoId: ""),
        Genre(name: "Singer/Songwriter", playlistId: "ft-playlist--65deec75-f2c1-4a2d-95d4-d38f78d42754", firstVideoId: ""),
        Genre(name: "World", playlistId: "ft-playlist--9089cade-980f-484b-a9f2-3b3951d68554", firstVideoId: ""),
        Genre(name: "Soundtrack", playlistId: "ft-playlist--6a1d1c44-01fb-4410-a152-51de98fdc4d8", firstVideoId: ""),
        Genre(name: "Russian Rap", playlistId: "ft-playlist--e318ffef-84db-4e77-9fd8-ecbd427b6168", firstVideoId: ""),
        Genre(name: "Russian Pop", playlistId: "ft-playlist--c2fbb61e-369d-4403-ae12-f323d965b998", firstVideoId: ""),
        Genre(name: "Radio Mix", playlistId: "ft-playlist--b3f8026b-4773-43a6-9f35-a477dca1b96d", firstVideoId: ""),
    ]
}
