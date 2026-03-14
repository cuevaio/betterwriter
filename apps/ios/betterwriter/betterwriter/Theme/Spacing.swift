import SwiftUI

enum Spacing {
  static let xs: CGFloat = 4
  static let s: CGFloat = 8
  static let m: CGFloat = 16
  static let l: CGFloat = 24
  static let xl: CGFloat = 32
  static let xxl: CGFloat = 48
  static let xxxl: CGFloat = 64

  /// Standard horizontal padding for content
  static let contentHorizontal: CGFloat = 24

  /// Extra horizontal padding for reading text (book-page feel)
  static let readingHorizontal: CGFloat = 32

  /// TextEditor placeholder vertical alignment inset
  static let textEditorTopInset: CGFloat = 8

  /// TextEditor placeholder horizontal alignment inset
  static let textEditorLeadingInset: CGFloat = 5

  /// Minimum spacer height for centered content (loading/error states)
  static let centeredMinSpacer: CGFloat = 120

  /// Minimum height for TextEditor in writing views
  static let textEditorMinHeight: CGFloat = 300

  /// Focus delay for text editor (nanoseconds)
  static let focusDelayNs: UInt64 = 600_000_000
}
