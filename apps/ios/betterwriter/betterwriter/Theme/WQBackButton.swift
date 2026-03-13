import SwiftUI

/// Inline "Back" button used for state-machine navigation (e.g. returning to DoneView).
///
/// Renders a left-aligned text button below the global brand bar with consistent
/// styling from the design system (Typography, WQColor, Spacing).
struct WQBackButton: View {
  let action: () -> Void

  var body: some View {
    HStack {
      Button(action: action) {
        Text("Back")
          .font(Typography.sansBody)
          .foregroundStyle(WQColor.primary)
      }
      Spacer()
    }
    .padding(.horizontal, Spacing.contentHorizontal)
    .padding(.top, Spacing.s)
    .padding(.bottom, Spacing.xs)
  }
}
