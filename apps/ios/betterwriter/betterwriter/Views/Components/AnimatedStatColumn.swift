import SwiftUI

/// Animated stat column with SF Symbol, rolling number counter, and label.
/// Numbers animate from 0 to target with a spring animation when `animate` flips to true.
/// Pass `skipAnimation: true` to display the target value instantly (no count-up).
struct AnimatedStatColumn: View {
  let targetValue: Int
  let label: String
  let symbolName: String
  @Binding var animate: Bool
  let skipAnimation: Bool

  @State private var displayValue: Int

  init(
    targetValue: Int,
    label: String,
    symbolName: String,
    animate: Binding<Bool>,
    skipAnimation: Bool = false
  ) {
    self.targetValue = targetValue
    self.label = label
    self.symbolName = symbolName
    self._animate = animate
    self.skipAnimation = skipAnimation
    self._displayValue = State(
      initialValue: skipAnimation ? targetValue : 0)
  }

  var body: some View {
    VStack(spacing: Spacing.xs) {
      // SF Symbol with bounce effect
      Image(systemName: symbolName)
        .font(.body)
        .foregroundStyle(WQColor.secondary)
        .symbolEffect(
          .bounce, value: skipAnimation ? false : animate)

      // Animated number
      Text("\(displayValue)")
        .font(Typography.statNumber)
        .foregroundStyle(WQColor.primary)
        .contentTransition(
          .numericText(value: Double(displayValue)))

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
      if skipAnimation {
        displayValue = targetValue
      } else {
        withAnimation(
          .spring(response: 0.8, dampingFraction: 0.8)
        ) {
          displayValue = targetValue
        }
      }
    }
  }
}
