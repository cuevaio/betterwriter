import Foundation
import SwiftData

/// Handles syncing local SwiftData state with the server.
/// Entries with `needsSync = true` are uploaded on app foreground.
@MainActor
final class SyncService {
  static let shared = SyncService()

  private init() {}

  /// Sync entries that need to be uploaded to the server.
  func syncPendingEntries(
    entries: [DayEntry],
    profile: UserProfile?,
    modelContext: ModelContext
  ) async {
    let pending = entries.filter { $0.needsSync }
    guard !pending.isEmpty || profile != nil else { return }

    do {
      // Build user updates
      var userUpdates: [String: Any]?
      if let profile = profile {
        userUpdates = [
          "currentStreak": profile.currentStreak,
          "longestStreak": profile.longestStreak,
          "totalWordsWritten": profile.totalWordsWritten,
          "onboardingDay0Done": profile.onboardingDay0Done,
          "onboardingDay1Done": profile.onboardingDay1Done,
        ]
      }

      // Build entry updates — dayIndex per entry echoes server-assigned values
      let dateFormatter = ISO8601DateFormatter()
      let entryUpdates: [[String: Any]] = pending.map { entry in
        var dict: [String: Any] = [
          "dayIndex": entry.dayIndex,
          "calendarDate": dateFormatter.string(from: entry.calendarDate),
          "readingCompleted": entry.readingCompleted,
          "writingCompleted": entry.writingCompleted,
          "writingWordCount": entry.writingWordCount,
          "isBonusReading": entry.isBonusReading,
          "isFreeWrite": entry.isFreeWrite,
          "skipped": entry.skipped,
        ]
        if let text = entry.writingText { dict["writingText"] = text }
        if let prompt = entry.writingPrompt { dict["writingPrompt"] = prompt }
        return dict
      }

      let response = try await APIClient.shared.sync(
        user: userUpdates,
        entries: entryUpdates.isEmpty ? nil : entryUpdates
      )

      // Mark entries as synced
      for entry in pending {
        entry.needsSync = false
      }
      try? modelContext.save()

      if let serverDay = response.currentDayIndex {
        print("SyncService: Synced \(pending.count) entries, server currentDayIndex=\(serverDay)")
      } else {
        print("SyncService: Synced \(pending.count) entries")
      }
    } catch {
      print("SyncService: Sync failed: \(error)")
      // Entries remain needsSync = true for next attempt
    }
  }
}
