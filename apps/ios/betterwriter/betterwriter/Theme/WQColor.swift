import SwiftUI

enum WQColor {
    /// Primary foreground: adaptive black (light) / white (dark)
    static let primary = Color.primary

    /// Background: adaptive white (light mode) / black (dark mode).
    /// Equivalent to the system background. Use `.background` view modifier or this value.
    static let background = Color("AppBackground")

    /// Secondary text: gray for captions, dates, word counts
    static let secondary = Color.secondary

    /// Calendar: completed day fill
    static let completedDay = Color.primary

    /// Calendar: skipped/missed day
    static let skippedDay = Color.primary.opacity(0.15)

    /// Calendar: future day
    static let futureDay = Color.primary.opacity(0.05)

    /// Placeholder text
    static let placeholder = Color.primary.opacity(0.3)

    /// Primary action button border
    static let border = Color.primary

    /// Secondary/lighter button border
    static let borderLight = Color.primary.opacity(0.3)

    // MARK: - Activity chart levels (green shades, GitHub-style)

    /// No activity
    static let activityLevel0 = Color.primary.opacity(0.06)
    /// Low activity
    static let activityLevel1 = Color.green.opacity(0.35)
    /// Medium activity
    static let activityLevel2 = Color.green.opacity(0.55)
    /// High activity
    static let activityLevel3 = Color.green.opacity(0.75)
    /// Very high activity
    static let activityLevel4 = Color.green.opacity(1.0)
}
