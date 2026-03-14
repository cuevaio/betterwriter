import SwiftUI

enum WQColor {
  // MARK: - Core

  /// Primary foreground: warm off-black (light) / warm off-white (dark)
  static let primary = Color("AppForeground")

  /// Background: warm ivory (light) / warm near-black (dark)
  static let background = Color("AppBackground")

  /// Secondary text: captions, dates, word counts
  static let secondary = Color("AppForeground").opacity(0.55)

  /// Tertiary text: subtle hints
  static let tertiary = Color("AppForeground").opacity(0.35)

  /// Placeholder text
  static let placeholder = Color("AppForeground").opacity(0.25)

  // MARK: - Interactive

  /// Primary action button border / fill
  static let border = Color("AppForeground")

  /// Secondary / lighter button border
  static let borderLight = Color("AppForeground").opacity(0.25)

  /// Subtle divider lines
  static let divider = Color("AppForeground").opacity(0.1)

  // MARK: - Activity chart levels (monochrome, unified)

  /// No activity
  static let activityLevel0 = Color("AppForeground").opacity(0.06)
  /// Low activity
  static let activityLevel1 = Color("AppForeground").opacity(0.2)
  /// Medium activity
  static let activityLevel2 = Color("AppForeground").opacity(0.4)
  /// High activity
  static let activityLevel3 = Color("AppForeground").opacity(0.65)
  /// Very high activity
  static let activityLevel4 = Color("AppForeground").opacity(0.9)
}
