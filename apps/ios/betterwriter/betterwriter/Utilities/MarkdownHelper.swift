import Foundation

/// Shared markdown-to-AttributedString helper.
enum MarkdownHelper {
  /// Parse inline markdown into an `AttributedString`.
  /// Falls back to plain text if parsing fails.
  static func attributedString(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .full
    )
    return (try? AttributedString(markdown: text, options: options))
      ?? AttributedString(text)
  }
}
