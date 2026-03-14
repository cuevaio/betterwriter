import SwiftUI

/// Shared markdown content renderer with consistent styling.
/// Replaces the duplicated inline `markdownContent(text:)` across ReadView and BonusReadView.
struct WQMarkdownContent: View {
  let text: String

  /// Matches the trailing link appended by the server:
  /// `[Read the full article on host](url)`
  private static let trailingLinkPattern = try! NSRegularExpression(
    pattern: #"\n{0,2}\[Read the full article on ([^\]]+)\]\((https?://[^)]+)\)\s*$"#,
    options: []
  )

  /// Split `text` into (bodyWithoutLink, label, url) if a trailing link is present.
  private var parts: (body: String, label: String, url: URL)? {
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard
      let match = Self.trailingLinkPattern.firstMatch(in: text, range: range),
      match.numberOfRanges == 3,
      let labelRange = Range(match.range(at: 1), in: text),
      let urlRange = Range(match.range(at: 2), in: text),
      let url = URL(string: String(text[urlRange]))
    else { return nil }

    let body = String(
      text[text.startIndex..<text.index(text.startIndex, offsetBy: match.range.location)])
    let label = String(text[labelRange])
    return (body, "Read the full article on \(label)", url)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      if let (body, label, url) = parts {
        bodyText(body)
        Link(label, destination: url)
          .font(Typography.serifBody)
          .foregroundColor(.accentColor)
          .underline()
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        bodyText(text)
      }
    }
  }

  private func bodyText(_ content: String) -> some View {
    Text(MarkdownHelper.attributedString(content))
      .font(Typography.serifBody)
      .lineSpacing(Typography.readingLineSpacing)
      .foregroundColor(WQColor.primary)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
