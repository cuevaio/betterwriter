import Foundation
import SwiftData

@Model
final class DayEntry: Identifiable {
  static let bonusIndexBase = 100_000
  static let freeWriteIndexBase = 200_000

  @Attribute(.unique) var id: UUID
  var dayIndex: Int
  var calendarDate: Date

  // Reading
  var readingBody: String?
  var readingCompleted: Bool
  /// Partial text accumulated during an active SSE stream.
  /// Cleared when readingBody is set (stream completed).
  var readingBodyDraft: String?

  // Writing
  var writingPrompt: String?
  var writingText: String?
  var writingWordCount: Int
  var writingCompleted: Bool

  // Metadata
  var isBonusReading: Bool
  var isFreeWrite: Bool
  var skipped: Bool

  // Sync
  var needsSync: Bool

  init(
    id: UUID = UUID(),
    dayIndex: Int,
    calendarDate: Date = Date(),
    readingBody: String? = nil,
    readingCompleted: Bool = false,
    readingBodyDraft: String? = nil,
    writingPrompt: String? = nil,
    writingText: String? = nil,
    writingWordCount: Int = 0,
    writingCompleted: Bool = false,
    isBonusReading: Bool = false,
    isFreeWrite: Bool = false,
    skipped: Bool = false,
    needsSync: Bool = true
  ) {
    self.id = id
    self.dayIndex = dayIndex
    self.calendarDate = calendarDate
    self.readingBody = readingBody
    self.readingCompleted = readingCompleted
    self.readingBodyDraft = readingBodyDraft
    self.writingPrompt = writingPrompt
    self.writingText = writingText
    self.writingWordCount = writingWordCount
    self.writingCompleted = writingCompleted
    self.isBonusReading = isBonusReading
    self.isFreeWrite = isFreeWrite
    self.skipped = skipped
    self.needsSync = needsSync
  }

  /// Whether this entry uses a synthetic dayIndex (bonus read or free write).
  var isSyntheticEntry: Bool {
    dayIndex >= DayEntry.bonusIndexBase
  }

  /// Word count computed from readingBody
  var readingWordCount: Int {
    guard let body = readingBody, !body.isEmpty else { return 0 }
    return body.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }.count
  }
}
