import SwiftUI

/// Shared markdown content renderer with consistent styling.
/// Replaces the duplicated inline `markdownContent(text:)` across ReadView and BonusReadView.
struct WQMarkdownContent: View {
  let text: String

  var body: some View {
    Text(MarkdownHelper.attributedString(text))
      .font(Typography.serifBody)
      .lineSpacing(Typography.readingLineSpacing)
      .foregroundStyle(WQColor.primary)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
