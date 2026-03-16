import Inject
import SwiftUI

struct BrandWordmarkView: View {
  @ObserveInjection var inject
  var compact: Bool = false

  var body: some View {
    Text("betterwriter")
      .font(compact ? Typography.brandWordmarkCompact : Typography.brandWordmark)
      .foregroundStyle(WQColor.secondary)
      .tracking(compact ? 0.5 : 1.2)
      .textCase(.lowercase)
      .accessibilityLabel("betterwriter")
      .enableInjection()
  }
}
