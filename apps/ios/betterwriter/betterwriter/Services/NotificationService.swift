import Foundation
import UserNotifications

/// Manages local daily reminder notifications.
enum NotificationService {
  // MARK: - Notification slots

  private struct Slot {
    let hour: Int
    let minute: Int
    let identifier: String
    let messages: [String]
  }

  private static let slots: [Slot] = [
    Slot(
      hour: 7,
      minute: 0,
      identifier: "daily-reminder-7am",
      messages: [
        "Morning. The page is blank. That's on you.",
        "Rise and read. Your future self is watching.",
        "Good morning! Your reading is ready — coffee optional.",
        "The early bird gets the words. Let's go.",
        "Day not yet ruined. Perfect time to read.",
      ]
    ),
    Slot(
      hour: 11,
      minute: 0,
      identifier: "daily-reminder-11am",
      messages: [
        "Still haven't read today? Bold choice.",
        "Halfway to noon and still no reading. Just saying.",
        "You've checked your phone 47 times. One of those could've been this.",
        "Pre-lunch reading hit different. Trust the process.",
        "Your streak won't maintain itself. Friendly reminder.",
      ]
    ),
    Slot(
      hour: 15,
      minute: 0,
      identifier: "daily-reminder-3pm",
      messages: [
        "Afternoon slump? Reading fixes that (probably).",
        "Three PM. You know what to do.",
        "The words aren't going to read themselves. Unfortunately.",
        "Quick break, quick read, quick win. Do it.",
        "You made it past lunch. Celebrate with today's reading.",
      ]
    ),
    Slot(
      hour: 21,
      minute: 0,
      identifier: "daily-reminder-9pm",
      messages: [
        "Day's almost done. Don't let it slip by.",
        "Reading before bed beats doomscrolling. Marginally.",
        "Last call for today's reading. Don't blow it.",
        "Tomorrow's version of you will be grateful. Tonight.",
        "You're this close to keeping the streak alive.",
      ]
    ),
  ]

  // MARK: - Public API

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

  /// Schedule all four daily notifications. Each slot rotates through its own
  /// message pool based on `dayIndex`.
  static func scheduleAllReminders(dayIndex: Int = 0) {
    let center = UNUserNotificationCenter.current()

    for slot in slots {
      // Remove any existing notification for this slot before rescheduling.
      center.removePendingNotificationRequests(withIdentifiers: [slot.identifier])

      let content = UNMutableNotificationContent()
      content.title = "Better Writer"
      content.body = slot.messages[dayIndex % slot.messages.count]
      content.sound = .default

      var dateComponents = DateComponents()
      dateComponents.hour = slot.hour
      dateComponents.minute = slot.minute

      let trigger = UNCalendarNotificationTrigger(
        dateMatching: dateComponents,
        repeats: true
      )

      let request = UNNotificationRequest(
        identifier: slot.identifier,
        content: content,
        trigger: trigger
      )

      center.add(request) { error in
        if let error = error {
          print("NotificationService: Failed to schedule \(slot.identifier): \(error)")
        }
      }
    }
  }

  /// Cancel all pending notifications.
  static func cancelAll() {
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
  }
}
