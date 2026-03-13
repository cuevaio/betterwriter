import SwiftUI

enum Typography {
    // MARK: - Serif (reading content)

    /// Large title for reading passages
    static let serifTitle: Font = .system(.title, design: .serif, weight: .semibold)

    /// Body text for reading passages — use with .lineSpacing(6)
    static let serifBody: Font = .system(.body, design: .serif)

    /// Large serif for hero text on Done screen
    static let serifLargeTitle: Font = .system(.largeTitle, design: .serif, weight: .regular)

    // MARK: - Sans-serif (UI elements)

    /// Standard UI body text
    static let sansBody: Font = .system(.body)

    /// Button text
    static let sansButton: Font = .system(.body, weight: .semibold)

    /// Caption text (word count, dates)
    static let sansCaption: Font = .system(.caption)

    /// Stat numbers
    static let statNumber: Font = .system(.title, design: .rounded, weight: .bold)

    /// Stat labels
    static let statLabel: Font = .system(.caption2, weight: .medium)

    // MARK: - Chart

    /// Month labels and legend text in activity chart
    static let chartLabel: Font = .system(size: 10)

    /// Day-of-week labels (Mon/Wed/Fri) in activity chart
    static let chartDayLabel: Font = .system(size: 9)

    // MARK: - Brand

    /// Primary wordmark style used in app chrome
    static let brandWordmark: Font = .system(size: 15, weight: .semibold, design: .serif)

    /// Compact wordmark for toolbars/navigation bars
    static let brandWordmarkCompact: Font = .system(size: 13, weight: .semibold, design: .serif)
}
