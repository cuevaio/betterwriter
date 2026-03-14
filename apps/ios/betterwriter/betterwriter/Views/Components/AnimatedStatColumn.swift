import SwiftUI

/// Animated stat column with SF Symbol, rolling number counter, and label.
/// Numbers animate from 0 to target with a spring animation when `animate` flips to true.
struct AnimatedStatColumn: View {
  let targetValue: Int
  let label: String
  let symbolName: String
  @Binding var animate: Bool

  @State private var displayValue: Int = 0

  var body: some View {
    VStack(spacing: Spacing.xs) {
      // SF Symbol with bounce effect
      Image(systemName: symbolName)
        .font(.body)
        .foregroundStyle(WQColor.secondary)
        .symbolEffect(.bounce, value: animate)

      // Animated number
      Text("\(displayValue)")
        .font(Typography.statNumber)
        .foregroundStyle(WQColor.primary)
        .contentTransition(.numericText(value: Double(displayValue)))

      // Label
      Text(label)
        .font(Typography.statLabel)
        .foregroundStyle(WQColor.secondary)
        .textCase(.uppercase)
        .tracking(1)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .onChange(of: animate) { _, shouldAnimate in
      guard shouldAnimate else { return }
      withAnimation(
        .spring(response: 0.8, dampingFraction: 0.8)
      ) {
        displayValue = targetValue
      }
    }
  }
}
