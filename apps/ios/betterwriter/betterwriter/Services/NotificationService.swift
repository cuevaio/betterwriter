import Foundation
import UserNotifications

/// Manages local daily reminder notifications.
enum NotificationService {
    private static let dailyReminderId = "daily-reminder"

    private static let messages = [
        "Your reading is ready.",
        "A few minutes of reading, a few of writing.",
        "Pick up where you left off.",
        "Today's text is waiting.",
        "Read. Remember. Write.",
    ]

    /// Request notification permission from the user.
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            print("NotificationService: Authorization request failed: \(error)")
            return false
        }
    }

    /// Schedule a repeating daily notification at the given time.
    static func scheduleDailyReminder(hour: Int = 9, minute: Int = 0, dayIndex: Int = 0) {
        let center = UNUserNotificationCenter.current()

        // Remove existing
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderId])

        let content = UNMutableNotificationContent()
        content.title = "Better Writer"
        content.body = messages[dayIndex % messages.count]
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: dailyReminderId,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("NotificationService: Failed to schedule: \(error)")
            }
        }
    }

    /// Cancel all pending notifications.
    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
