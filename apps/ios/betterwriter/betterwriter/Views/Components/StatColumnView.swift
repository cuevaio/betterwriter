import SwiftUI

/// Reusable stat column showing a numeric value and label.
/// Used in DoneView's inline stats section.
struct StatColumnView: View {
  let value: String
  let label: String

  var body: some View {
    VStack(spacing: Spacing.xs) {
      Text(value)
        .font(Typography.statNumber)
        .foregroundStyle(WQColor.primary)
      Text(label)
        .font(Typography.statLabel)
        .foregroundStyle(WQColor.secondary)
        .textCase(.uppercase)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}
