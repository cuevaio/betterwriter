import SwiftUI

/// GitHub-style activity contribution chart.
/// Fills the available width exactly — number of weeks and cell size are derived
/// from the container width so the chart never overflows or scrolls.
struct ActivityChartView: View {
    let entries: [DayEntry]
    /// Unused — kept for call-site compatibility during migration.
    var profile: UserProfile? = nil

    private let cellSpacing: CGFloat = 3
    private let dayLabelWidth: CGFloat = 28
    private let calendar = Calendar.current

    // MARK: - Data helpers

    private var entryByDate: [DateComponents: DayEntry] {
        var map: [DateComponents: DayEntry] = [:]
        for entry in entries where !entry.isBonusReading && !entry.skipped {
            let comps = calendar.dateComponents([.year, .month, .day], from: entry.calendarDate)
            if let existing = map[comps] {
                let existingWords = existing.readingWordCount + existing.writingWordCount
                let newWords = entry.readingWordCount + entry.writingWordCount
                if newWords > existingWords { map[comps] = entry }
            } else {
                map[comps] = entry
            }
        }
        return map
    }

    private func buildGrid(weeksToShow: Int) -> [[Date?]] {
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        let daysUntilSat = (7 - todayWeekday) % 7
        let endDate = calendar.date(byAdding: .day, value: daysUntilSat, to: today)!
        let startDate = calendar.date(byAdding: .day, value: -(weeksToShow * 7 - 1), to: endDate)!

        var grid: [[Date?]] = []
        var currentDate = startDate
        while currentDate <= endDate {
            let weekday = calendar.component(.weekday, from: currentDate)
            if weekday == 1 || grid.isEmpty {
                grid.append(Array(repeating: nil, count: 7))
            }
            let col = grid.count - 1
            let row = weekday - 1
            grid[col][row] = currentDate > today ? nil : currentDate
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        return grid
    }

    private func monthLabels(for grid: [[Date?]]) -> [(String, Int)] {
        var labels: [(String, Int)] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        var lastMonth = -1
        for (colIndex, week) in grid.enumerated() {
            guard let firstDate = week.compactMap({ $0 }).first else { continue }
            let month = calendar.component(.month, from: firstDate)
            if month != lastMonth {
                labels.append((formatter.string(from: firstDate), colIndex))
                lastMonth = month
            }
        }
        return labels
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let gridWidth = availableWidth - dayLabelWidth - cellSpacing
            let minCellSize: CGFloat = 10
            let weeksToShow = max(1, Int(gridWidth / (minCellSize + cellSpacing)))
            let cellSize = (gridWidth - CGFloat(weeksToShow - 1) * cellSpacing) / CGFloat(weeksToShow)
            let grid = buildGrid(weeksToShow: weeksToShow)
            let lookup = entryByDate
            let labels = monthLabels(for: grid)

            ActivityChartGrid(
                grid: grid,
                lookup: lookup,
                labels: labels,
                cellSize: cellSize,
                cellSpacing: cellSpacing,
                dayLabelWidth: dayLabelWidth,
                gridWidth: gridWidth
            )
        }
        .frame(height: activityChartHeight)
    }

    private var activityChartHeight: CGFloat {
        let monthRowHeight: CGFloat = 14
        let cellSize: CGFloat = 10  // minimum; actual is larger but height is the same
        let gridHeight = 7 * cellSize + 6 * cellSpacing
        let legendHeight: CGFloat = 14
        return monthRowHeight + Spacing.s + gridHeight + Spacing.s + legendHeight
    }
}

// MARK: - Inner grid view (extracted to help the type checker)

private struct ActivityChartGrid: View {
    let grid: [[Date?]]
    let lookup: [DateComponents: DayEntry]
    let labels: [(String, Int)]
    let cellSize: CGFloat
    let cellSpacing: CGFloat
    let dayLabelWidth: CGFloat
    let gridWidth: CGFloat

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            monthLabelsRow
            gridRow
            legendRow
        }
    }

    private var monthLabelsRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: dayLabelWidth + cellSpacing, height: 14)
            ZStack(alignment: .leading) {
                Color.clear.frame(width: gridWidth, height: 14)
                ForEach(labels, id: \.1) { item in
                    Text(item.0)
                        .font(Typography.chartLabel)
                        .foregroundStyle(WQColor.secondary)
                        .offset(x: CGFloat(item.1) * (cellSize + cellSpacing))
                }
            }
        }
    }

    private var gridRow: some View {
        HStack(alignment: .top, spacing: cellSpacing) {
            dayLabelsColumn
            weekColumnsGrid
        }
    }

    private var dayLabelsColumn: some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { row in
                dayLabel(for: row)
                    .font(Typography.chartDayLabel)
                    .foregroundStyle(WQColor.secondary)
                    .frame(width: dayLabelWidth, height: cellSize, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func dayLabel(for row: Int) -> some View {
        switch row {
        case 1: Text("Mon")
        case 3: Text("Wed")
        case 5: Text("Fri")
        default: Text("").hidden()
        }
    }

    private var weekColumnsGrid: some View {
        HStack(spacing: cellSpacing) {
            ForEach(0..<grid.count, id: \.self) { colIndex in
                weekColumn(colIndex: colIndex)
            }
        }
    }

    private func weekColumn(colIndex: Int) -> some View {
        VStack(spacing: cellSpacing) {
            ForEach(0..<7, id: \.self) { row in
                cell(colIndex: colIndex, row: row)
            }
        }
    }

    private func cell(colIndex: Int, row: Int) -> some View {
        let date = grid[colIndex][row]
        let fillColor = cellColor(for: date)
        return RoundedRectangle(cornerRadius: 2)
            .fill(fillColor)
            .frame(width: cellSize, height: cellSize)
    }

    private func cellColor(for date: Date?) -> Color {
        guard let date = date else { return Color.clear }
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let level = activityLevel(for: lookup[comps])
        return colorForLevel(level)
    }

    private var legendRow: some View {
        HStack(spacing: Spacing.s) {
            Spacer()
            Text("Less")
                .font(Typography.chartLabel)
                .foregroundStyle(WQColor.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(colorForLevel(level))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("More")
                .font(Typography.chartLabel)
                .foregroundStyle(WQColor.secondary)
        }
    }

    private func activityLevel(for entry: DayEntry?) -> Int {
        guard let entry = entry else { return 0 }
        let total = entry.readingWordCount + entry.writingWordCount
        if total == 0 { return 0 }
        if total < 100 { return 1 }
        if total < 300 { return 2 }
        if total < 600 { return 3 }
        return 4
    }

    private func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 1: return WQColor.activityLevel1
        case 2: return WQColor.activityLevel2
        case 3: return WQColor.activityLevel3
        case 4: return WQColor.activityLevel4
        default: return WQColor.activityLevel0
        }
    }
}
