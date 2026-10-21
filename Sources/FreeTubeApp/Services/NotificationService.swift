import Foundation
import UserNotifications

final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    private var authorized = false

    init() {
        requestAuthorization()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    func sendUpdateNotification(version: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "FreeTube Updated"
        content.body = "FreeTube was updated to version \(version). Open it when you're ready."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "freetube-update-\(version)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func sendChartsRefreshedNotification(count: Int) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "FreeTube Top Charts"
        content.body = "\(count) genre playlists refreshed."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "freetube-charts-\(Date().timeIntervalSince1970)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
