import SwiftUI
import SwiftData

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

    private var streak: Int {
        DayEngine.calculateStreak(entries: Array(entries))
    }

    private var wordsRead: Int {
        DayEngine.totalWordsRead(entries: Array(entries))
    }

    private var wordsWritten: Int {
        DayEngine.totalWordsWritten(entries: Array(entries))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Stats row — streak, words read, words written
                    HStack(spacing: Spacing.l) {
                        statColumn(value: "\(streak)", label: "Streak")
                        statColumn(value: "\(wordsRead)", label: "Read")
                        statColumn(value: "\(wordsWritten)", label: "Written")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.l)

                    // Activity chart
                    ActivityChartView(entries: Array(entries))

                    Spacer(minLength: Spacing.xxl)
                }
                .padding(.horizontal, Spacing.contentHorizontal)
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BrandWordmarkView(compact: true)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                        .foregroundStyle(WQColor.primary)
                }
            }
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(Typography.statNumber)
                .foregroundStyle(WQColor.primary)
            Text(label)
                .font(Typography.statLabel)
                .foregroundStyle(WQColor.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}
