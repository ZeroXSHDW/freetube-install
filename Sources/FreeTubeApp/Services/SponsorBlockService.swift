import Foundation

/// SponsorBlock integration — queries sponsor.ajay.app for the currently
/// playing video and auto-skips sponsor/self-promo/intro/outro segments
/// through the system media controls, so it works while FreeTube is playing.
@MainActor
final class SponsorBlockService: ObservableObject {
    static let shared = SponsorBlockService()

    struct Segment: Codable, Identifiable, Equatable {
        let category: String
        let segment: [Double]
        let uuid: String

        var id: String { uuid }
        var start: Double { segment.first ?? 0 }
        var end: Double { segment.last ?? 0 }

        var label: String {
            switch category {
            case "sponsor": return "Sponsor"
            case "selfpromo": return "Self-promo"
            case "intro": return "Intro"
            case "outro": return "Outro"
            case "interaction": return "Filler/Interaction"
            case "preview": return "Recap/Preview"
            case "music_offtopic": return "Non-music"
            default: return category.capitalized
            }
        }

        var skippedDuration: Int {
            max(0, Int(end - start))
        }
    }

    static let allCategories = ["sponsor", "selfpromo", "intro", "outro",
                                "interaction", "preview", "music_offtopic"]
    static let allCategoriesLabels: [String: String] = [
        "sponsor": "Sponsor", "selfpromo": "Self-promo", "intro": "Intro",
        "outro": "Outro", "interaction": "Filler/Interaction",
        "preview": "Recap/Preview", "music_offtopic": "Non-music"
    ]

    @Published var autoSkipEnabled: Bool {
        didSet { UserDefaults.standard.set(autoSkipEnabled, forKey: "sponsorBlock.autoSkip") }
    }
    @Published var skipToast: String?
    @Published var totalSkippedSeconds: Int {
        didSet { UserDefaults.standard.set(totalSkippedSeconds, forKey: "sponsorBlock.totalSkipped") }
    }

    /// Categories the user has chosen to auto-skip.
    private var enabledCategories: [String] {
        let defaults = UserDefaults.standard.array(forKey: "sponsorBlock.categories") as? [String]
            ?? ["sponsor", "selfpromo", "intro", "outro", "interaction", "preview", "music_offtopic"]
        return defaults
    }

    private var cache: [String: [Segment]] = [:]
    private var skippedUUIDs = Set<String>()
    private var resolvedVideoId: String?

    private init() {
        autoSkipEnabled = UserDefaults.standard.bool(forKey: "sponsorBlock.autoSkip")
        if UserDefaults.standard.object(forKey: "sponsorBlock.autoSkip") == nil {
            autoSkipEnabled = true
            UserDefaults.standard.set(true, forKey: "sponsorBlock.autoSkip")
        }
        totalSkippedSeconds = UserDefaults.standard.integer(forKey: "sponsorBlock.totalSkipped")
    }

    func reset(for videoId: String?) {
        resolvedVideoId = videoId
        skippedUUIDs.removeAll()
        skipToast = nil
    }

    /// Loads (and caches) the segments for a video.
    func segments(for videoId: String) async -> [Segment] {
        if let cached = cache[videoId] { return cached }
        let fetched = await fetchSegments(for: videoId)
        cache[videoId] = fetched
        return fetched
    }

    /// Called from the Now Playing loop; auto-skips any segment that just started.
    func observe(elapsed: Double, videoId: String?) {
        guard autoSkipEnabled, let videoId, !videoId.isEmpty else { return }
        guard elapsed >= 0, elapsed < 60 * 60 * 12 else { return }
        Task {
            let list = await self.segments(for: videoId)
            self.applyAutoSkip(elapsed: elapsed, segments: list)
        }
    }

    private func applyAutoSkip(elapsed: Double, segments: [Segment]) {
        for segment in segments {
            guard !skippedUUIDs.contains(segment.uuid),
                  enabledCategories.contains(segment.category) else { continue }
            let window = 1.2
            if elapsed >= segment.start - 0.1 && elapsed < segment.start + window {
                skip(segment)
            }
            // If playback started inside a segment, skip out immediately.
            if elapsed > segment.start && elapsed < segment.end {
                skip(segment)
            }
        }
    }

    private func skip(_ segment: Segment) {
        skippedUUIDs.insert(segment.uuid)
        let target = Int(segment.end.rounded())
        _ = try? ShellHelper.runNamed("nowplaying-cli", arguments: ["seek", "\(target)"])
        totalSkippedSeconds += segment.skippedDuration
        skipToast = "⏭ Skipped \(segment.label) (\(segment.skippedDuration)s)"
    }

    // MARK: - Networking

    private func fetchSegments(for videoId: String) async -> [Segment] {
        var components = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments")
        let categoriesJSON = "[" + enabledCategories.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        components?.queryItems = [
            URLQueryItem(name: "videoID", value: videoId),
            URLQueryItem(name: "categories", value: categoriesJSON)
        ]
        guard let url = components?.url else { return [] }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return try JSONDecoder().decode([Segment].self, from: data)
        } catch {
            return []
        }
    }
}
