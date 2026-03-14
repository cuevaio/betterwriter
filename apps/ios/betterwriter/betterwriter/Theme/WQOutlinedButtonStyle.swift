import SwiftUI

/// Outlined button style used throughout the app.
///
/// - Primary (default): full-opacity border for action buttons
/// - Secondary (`isSecondary: true`): lighter border for menu-style buttons
/// - Filled (`isFilled: true`): inverted fill for primary CTAs (DONE READING, DONE WRITING)
struct WQOutlinedButtonStyle: ButtonStyle {
  var isSecondary: Bool = false
  var isFilled: Bool = false

  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(Typography.sansButton)
      .tracking(1.5)
      .foregroundStyle(
        isFilled ? WQColor.background : WQColor.primary
      )
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.m)
      .background(
        isFilled ? WQColor.primary : Color.clear
      )
      .clipShape(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .stroke(
            isSecondary ? WQColor.borderLight : WQColor.border,
            lineWidth: isFilled ? 0 : 1
          )
      )
      .opacity(isEnabled ? 1 : 0.35)
      .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
      .opacity(configuration.isPressed ? 0.85 : 1.0)
      .animation(
        .spring(response: 0.25, dampingFraction: 0.7),
        value: configuration.isPressed
      )
  }
}
