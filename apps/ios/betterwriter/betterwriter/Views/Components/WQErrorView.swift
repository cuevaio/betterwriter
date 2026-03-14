import SwiftUI

/// Shared error state view with optional retry action.
/// Replaces the duplicated inline `errorView` across ReadView, BonusReadView, and WriteView.
struct WQErrorView: View {
  let message: String
  var retryAction: (() -> Void)?

  var body: some View {
    VStack(spacing: Spacing.m) {
      Image(systemName: "exclamationmark.triangle")
        .font(.title2)
        .foregroundStyle(WQColor.secondary)

      Text(message)
        .font(Typography.sansBody)
        .foregroundStyle(WQColor.secondary)
        .multilineTextAlignment(.center)

      if let retry = retryAction {
        Button("Try again", action: retry)
          .font(Typography.sansButton)
          .foregroundStyle(WQColor.primary)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(maxHeight: .infinity)
  }
}
