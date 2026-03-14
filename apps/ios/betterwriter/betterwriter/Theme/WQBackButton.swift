import SwiftUI

/// Inline back button used for state-machine navigation (e.g. returning to DoneView).
///
/// Renders a left-aligned chevron + text button below the global brand bar with consistent
/// styling from the design system.
struct WQBackButton: View {
  let action: () -> Void

  var body: some View {
    HStack {
      Button(action: action) {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "chevron.left")
            .font(.system(size: 15, weight: .medium))
          Text("Back")
            .font(Typography.sansBody)
        }
        .foregroundStyle(WQColor.primary)
      }
      Spacer()
    }
    .padding(.horizontal, Spacing.contentHorizontal)
    .padding(.top, Spacing.s)
    .padding(.bottom, Spacing.xs)
  }
}
