import Foundation

/// The app states, plus a loading state.
enum AppPhase: Equatable {
    /// User needs to read today's text
    case read(dayIndex: Int)
    /// User needs to write about a past reading
    case write(dayIndex: Int, aboutDayIndex: Int)
    /// User has completed today's cycle
    case done(dayIndex: Int)
    /// User is reading a bonus text after completing the day
    case bonusRead(dayIndex: Int)
    /// User is doing a free-form write after completing the day
    case freeWrite(dayIndex: Int)
    /// App is loading/initializing
    case loading
}
