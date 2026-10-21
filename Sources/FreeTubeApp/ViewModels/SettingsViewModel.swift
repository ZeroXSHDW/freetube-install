import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    let configService = ConfigService.shared

    @Published var showingResetAlert = false

    func save() throws {
        try configService.saveConfig()
    }

    func resetDefaults() {
        configService.resetToDefaults()
    }

    var backendPreference: String {
        get { configService.config.backendPreference }
        set { configService.config.backendPreference = newValue }
    }

    var backendFallback: Bool {
        get { configService.config.backendFallback }
        set { configService.config.backendFallback = newValue }
    }

    var useRSS: Bool {
        get { configService.config.useRssFeeds }
        set { configService.config.useRssFeeds = newValue }
    }

    var defaultQuality: String {
        get { configService.config.defaultQuality }
        set { configService.config.defaultQuality = newValue }
    }

    var interruptionHours: Int {
        get { configService.config.defaultAutoplayInterruptionIntervalHours }
        set { configService.config.defaultAutoplayInterruptionIntervalHours = newValue }
    }

    var availableQualities = ["360", "480", "720", "1080"]
    var availableBackends = ["local", "invidious"]
}
