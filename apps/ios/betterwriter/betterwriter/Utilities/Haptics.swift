import UIKit

/// Centralized haptic feedback utility.
/// Use static methods to trigger feedback at key interaction points.
enum Haptics {
  private static let lightImpact = UIImpactFeedbackGenerator(
    style: .light)
  private static let mediumImpact = UIImpactFeedbackGenerator(
    style: .medium)
  private static let notification = UINotificationFeedbackGenerator()
  private static let selection = UISelectionFeedbackGenerator()

  /// Light tap — button presses, minor interactions
  static func light() { lightImpact.impactOccurred() }

  /// Medium tap — completing reading/writing
  static func medium() { mediumImpact.impactOccurred() }

  /// Success — completing the day cycle
  static func success() { notification.notificationOccurred(.success) }

  /// Selection tick — toggling, scrolling to snap points
  static func tick() { selection.selectionChanged() }
}
