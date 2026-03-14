import SwiftUI

/// Shared loading indicator with caption text.
/// Replaces the duplicated inline `loadingView` across ReadView, BonusReadView, and WriteView.
struct WQLoadingView: View {
  var caption: String = "Loading..."

  @State private var isPulsing = false

  var body: some View {
    VStack(spacing: Spacing.m) {
      ProgressView()
        .tint(WQColor.primary)
        .accessibilityLabel(caption)

      Text(caption)
        .font(Typography.sansCaption)
        .foregroundStyle(WQColor.secondary)
        .opacity(isPulsing ? 0.5 : 1.0)
        .animation(
          .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
          value: isPulsing
        )
        .onAppear { isPulsing = true }
    }
    .frame(maxWidth: .infinity)
    .frame(maxHeight: .infinity)
  }
}
