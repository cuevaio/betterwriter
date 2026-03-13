import SwiftUI

extension View {
  /// Adds a standard sheet toolbar with the brand wordmark at center and a dismiss
  /// button at the leading (cancellation) position.
  ///
  /// - Parameters:
  ///   - label: The dismiss button label. Defaults to "Close".
  ///   - action: The action to perform when the dismiss button is tapped.
  func wqSheetToolbar(
    dismiss label: String = "Close",
    action: @escaping () -> Void
  ) -> some View {
    self.toolbar {
      ToolbarItem(placement: .principal) {
        BrandWordmarkView(compact: true)
      }
      ToolbarItem(placement: .cancellationAction) {
        Button(label, action: action)
          .font(Typography.sansBody)
          .foregroundStyle(WQColor.primary)
      }
    }
  }
}
