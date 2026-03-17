import Foundation
import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.betterwriter", category: "DayEngine")

/// Resolves the current app phase based on user profile and entries.
enum DayEngine {

  /// Compute the current day index from local entries, mirroring the server algorithm.
  ///
  /// Completion-based model:
  /// - Find all normal entries (dayIndex < 100_000) where both reading and writing
  ///   are completed.
  /// - Current day = max(completed dayIndex) + 1.
  /// - If no completed entries exist, returns 0.
  static func computeCurrentDayIndex(entries: [DayEntry]) -> Int {
    let merged = deduplicatedEntries(entries)
    let completedNormal = merged.filter {
      !$0.isSyntheticEntry && $0.readingCompleted && $0.writingCompleted
    }
    guard let maxCompleted = completedNormal.map({ $0.dayIndex }).max() else {
      return 0
    }
    return maxCompleted + 1
  }

  /// Merge duplicate entries that share the same dayIndex by OR-ing their
  /// completion flags and taking the latest calendarDate. This handles the
  /// case where ReadView and WriteView each created separate DayEntry objects
  /// for the same dayIndex.
  private static func deduplicatedEntries(_ entries: [DayEntry]) -> [DayEntry] {
    var seen: [Int: DayEntry] = [:]
    for entry in entries {
      if let existing = seen[entry.dayIndex] {
        // Merge: keep whichever has the more complete state
        if entry.readingCompleted && !existing.readingCompleted {
          existing.readingCompleted = true
          existing.readingBody = existing.readingBody ?? entry.readingBody
          existing.readingBodyDraft = existing.readingBodyDraft ?? entry.readingBodyDraft
        }
        if entry.writingCompleted && !existing.writingCompleted {
          existing.writingCompleted = true
          existing.writingText = existing.writingText ?? entry.writingText
          existing.writingPrompt = existing.writingPrompt ?? entry.writingPrompt
          existing.writingWordCount = max(
            existing.writingWordCount, entry.writingWordCount)
        }
        // Use the later calendar date
        if entry.calendarDate > existing.calendarDate {
          existing.calendarDate = entry.calendarDate
        }
        existing.needsSync = true
        logger.warning("deduplicatedEntries: merged duplicate dayIndex=\(entry.dayIndex)")
      } else {
        seen[entry.dayIndex] = entry
      }
    }
    return Array(seen.values).sorted { $0.dayIndex < $1.dayIndex }
  }

  /// Determine what phase the app should be in right now.
  static func resolveCurrentPhase(
    profile: UserProfile?,
    entries: [DayEntry]
  ) -> AppPhase {
    guard profile != nil else {
      return .loading
    }

    let entries = deduplicatedEntries(entries)
    let todayIndex = computeCurrentDayIndex(entries: entries)
    logger.info("resolveCurrentPhase: todayIndex=\(todayIndex)")

    // If the user completed the previous day today, show the done view
    // before advancing to the next day's reading.
    if todayIndex > 0 {
      let prevIndex = todayIndex - 1
      let prevEntry = entries.first(where: { $0.dayIndex == prevIndex && !$0.isSyntheticEntry })
      if let prevEntry {
        let isToday = Calendar.current.isDateInToday(prevEntry.calendarDate)
        logger.info(
          "resolveCurrentPhase: prevEntry[\(prevIndex)] reading=\(prevEntry.readingCompleted) writing=\(prevEntry.writingCompleted) date=\(prevEntry.calendarDate.formatted(.iso8601)) isToday=\(isToday)"
        )
        if prevEntry.readingCompleted && prevEntry.writingCompleted && isToday {
          // Respect in-progress bonus/freewrite sessions
          if entries.contains(where: { $0.isBonusReading && !$0.readingCompleted }) {
            return .bonusRead(dayIndex: prevIndex)
          }
          if entries.contains(where: { $0.isFreeWrite && !$0.writingCompleted }) {
            return .freeWrite(dayIndex: prevIndex)
          }
          logger.info("resolveCurrentPhase: -> .done(dayIndex: \(prevIndex))")
          return .done(dayIndex: prevIndex)
        }
      } else {
        logger.info("resolveCurrentPhase: no prevEntry for index \(prevIndex)")
      }
    }

    // Get or conceptually create today's entry
    let todayEntry = entries.first { $0.dayIndex == todayIndex }
    logger.info("resolveCurrentPhase: todayEntry exists=\(todayEntry != nil)")

    // Step 1: Check if reading is done for today
    let readingDone = todayEntry?.readingCompleted ?? false

    // Step 2: Determine phase
    // Priority: read first, then write, then done
    if !readingDone {
      logger.info("resolveCurrentPhase: -> .read(dayIndex: \(todayIndex)) (reading not done)")
      return .read(dayIndex: todayIndex)
    }

    // Step 3: Check if today's writing is already done
    let writingDoneToday = todayEntry?.writingCompleted ?? false
    logger.info(
      "resolveCurrentPhase: readingDone=\(readingDone) writingDoneToday=\(writingDoneToday)")
    if writingDoneToday {
      // Check for an unread bonus entry (created by "Read something")
      if entries.contains(where: { $0.isBonusReading && !$0.readingCompleted }) {
        return .bonusRead(dayIndex: todayIndex)
      }

      // Check for an in-progress free write
      if entries.contains(where: { $0.isFreeWrite && !$0.writingCompleted }) {
        return .freeWrite(dayIndex: todayIndex)
      }

      return .done(dayIndex: todayIndex)
    }

    // Step 4: Check if there's a writing task context
    let writingTask = resolveWritingTask(
      entries: entries,
      todayIndex: todayIndex
    )

    if let aboutDayIndex = writingTask {
      logger.info(
        "resolveCurrentPhase: -> .write(dayIndex: \(todayIndex), aboutDayIndex: \(aboutDayIndex))")
      return .write(dayIndex: todayIndex, aboutDayIndex: aboutDayIndex)
    }

    // Check for an unread bonus entry
    if entries.contains(where: { $0.isBonusReading && !$0.readingCompleted }) {
      return .bonusRead(dayIndex: todayIndex)
    }

    return .done(dayIndex: todayIndex)
  }

  /// Determine which day's reading the user should write about today.
  /// Returns nil if there's no writing task.
  private static func resolveWritingTask(
    entries: [DayEntry],
    todayIndex: Int
  ) -> Int? {
    // Day 0: write self-introduction
    if todayIndex == 0 { return 0 }

    // Day 1: write clarifying day 0 intro
    if todayIndex == 1 { return 0 }

    // Day 2+: write about day n-2
    let aboutDayIndex = todayIndex - 2
    guard aboutDayIndex >= 0 else { return nil }

    let aboutEntry = entries.first { $0.dayIndex == aboutDayIndex }

    // Only offer writing if referenced reading exists and is completed
    guard aboutEntry?.readingCompleted == true else {
      return nil
    }

    return aboutDayIndex
  }

  /// Calculate the current day streak.
  /// A streak counts consecutive *calendar days* on which the user completed a full
  /// read+write cycle (writingCompleted == true on a non-bonus, non-skipped entry).
  /// Multiple completions on the same calendar day count as one day.
  static func calculateStreak(entries: [DayEntry]) -> Int {
    let calendar = Calendar.current

    // Collect the set of calendar days (year-month-day) on which writing was completed.
    let completedDays: Set<DateComponents> = Set(
      entries
        .filter { $0.writingCompleted && !$0.isBonusReading && !$0.isFreeWrite && !$0.skipped }
        .map { calendar.dateComponents([.year, .month, .day], from: $0.calendarDate) }
    )

    guard !completedDays.isEmpty else { return 0 }

    // Walk backwards from today, counting consecutive days that appear
    // in completedDays. Debug day override is now server-side only.
    var streak = 0
    var checkDate = calendar.startOfDay(for: Date())

    while true {
      let comps = calendar.dateComponents([.year, .month, .day], from: checkDate)
      if completedDays.contains(comps) {
        streak += 1
        checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
      } else {
        break
      }
    }

    return streak
  }

  /// Calculate total words written across all entries.
  static func totalWordsWritten(entries: [DayEntry]) -> Int {
    entries.reduce(0) { $0 + $1.writingWordCount }
  }

  /// Calculate total words read across all completed reading entries,
  /// including bonus reading sessions.
  static func totalWordsRead(entries: [DayEntry]) -> Int {
    entries.filter { $0.readingCompleted }
      .reduce(0) { $0 + $1.readingWordCount }
  }

  /// Calculate total days the user has completed the full read+write cycle.
  static func totalCompletedDays(entries: [DayEntry]) -> Int {
    entries.filter { $0.writingCompleted && !$0.isBonusReading && !$0.isFreeWrite }.count
  }
}
