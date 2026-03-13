import SwiftUI

/// Outlined button style used throughout the app.
///
/// - Primary (default): full-opacity border for action buttons (DONE WRITING, DONE READING, etc.)
/// - Secondary (`isSecondary: true`): lighter border for menu-style buttons (DoneView actions)
struct WQOutlinedButtonStyle: ButtonStyle {
    var isSecondary: Bool = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.sansButton)
            .tracking(2)
            .foregroundStyle(WQColor.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.m)
            .overlay(
                Rectangle()
                    .stroke(
                        isSecondary ? WQColor.borderLight : WQColor.border,
                        lineWidth: 1.5
                    )
            )
            .opacity(isEnabled ? 1 : 0.3)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
