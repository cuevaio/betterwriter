import Inject
import SwiftUI

/// GitHub-style activity contribution chart.
/// Fills the available width exactly — number of weeks and cell size are derived
/// from the container width so the chart never overflows or scrolls.
///
/// - Parameters:
///   - compact: When `true`, hides all labels and the legend, and fixes cells
///     to `compactCellSize` so the chart stays small. Used in DoneView.
///   - compactCellSize: Cell size (pt) when `compact` is true. Default 7.
struct ActivityChartView: View {
  @ObserveInjection var inject
  let entries: [DayEntry]
  var compact: Bool = false
  var compactCellSize: CGFloat = 7

  private let cellSpacing: CGFloat = 3
  private let dayLabelWidth: CGFloat = 28
  private let calendar = Calendar.current

  // MARK: - Data helpers

  /// Sum reading + writing words for all non-skipped entries per calendar day.
  private var wordsByDate: [DateComponents: Int] {
    var map: [DateComponents: Int] = [:]
    for entry in entries where !entry.skipped {
      let comps = calendar.dateComponents(
        [.year, .month, .day], from: entry.calendarDate)
      map[comps, default: 0] +=
        entry.readingWordCount + entry.writingWordCount
    }
    return map
  }

  private func buildGrid(weeksToShow: Int) -> [[Date?]] {
    let today = calendar.startOfDay(for: Date())
    let todayWeekday = calendar.component(.weekday, from: today)
    let daysUntilSat = (7 - todayWeekday) % 7
    let endDate = calendar.date(
      byAdding: .day, value: daysUntilSat, to: today)!
    let startDate = calendar.date(
      byAdding: .day, value: -(weeksToShow * 7 - 1), to: endDate)!

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
      currentDate = calendar.date(
        byAdding: .day, value: 1, to: currentDate)!
    }
    return grid
  }

  private func monthLabels(for grid: [[Date?]]) -> [(String, Int)] {
    var labels: [(String, Int)] = []
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM"
    var lastMonth = -1
    for (colIndex, week) in grid.enumerated() {
      guard let firstDate = week.compactMap({ $0 }).first
      else { continue }
      let month = calendar.component(.month, from: firstDate)
      if month != lastMonth {
        labels.append((formatter.string(from: firstDate), colIndex))
        lastMonth = month
      }
    }
    return labels
  }

  // MARK: - Body

  private var accessibilitySummary: String {
    let totalDays = entries.filter {
      $0.readingCompleted || $0.writingCompleted
    }.count
    let totalWords = entries.reduce(0) {
      $0 + $1.readingWordCount + $1.writingWordCount
    }
    return
      "Activity chart. \(totalDays) active days, \(totalWords) total words."
  }

  var body: some View {
    Group {
      if compact {
        GeometryReader { geo in
          let availableWidth = geo.size.width
          let weeksToShow = max(
            1,
            Int(
              (availableWidth + cellSpacing)
                / (compactCellSize + cellSpacing)))
          let grid = buildGrid(weeksToShow: weeksToShow)
          let lookup = wordsByDate

          ActivityChartGrid(
            grid: grid,
            lookup: lookup,
            labels: [],
            cellSize: compactCellSize,
            cellSpacing: cellSpacing,
            dayLabelWidth: 0,
            gridWidth: availableWidth,
            showLabels: false
          )
        }
        .frame(height: compactChartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
      } else {
        GeometryReader { geo in
          let availableWidth = geo.size.width
          let gridWidth = availableWidth - dayLabelWidth - cellSpacing
          let minCellSize: CGFloat = 10
          let weeksToShow = max(
            1, Int(gridWidth / (minCellSize + cellSpacing)))
          let cellSize =
            (gridWidth - CGFloat(weeksToShow - 1) * cellSpacing)
            / CGFloat(weeksToShow)
          let grid = buildGrid(weeksToShow: weeksToShow)
          let lookup = wordsByDate
          let labels = monthLabels(for: grid)

          ActivityChartGrid(
            grid: grid,
            lookup: lookup,
            labels: labels,
            cellSize: cellSize,
            cellSpacing: cellSpacing,
            dayLabelWidth: dayLabelWidth,
            gridWidth: gridWidth,
            showLabels: true
          )
        }
        .frame(height: fullChartHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
      }
    }
    .enableInjection()
  }

  private var compactChartHeight: CGFloat {
    7 * compactCellSize + 6 * cellSpacing
  }

  private var fullChartHeight: CGFloat {
    let minCellSize: CGFloat = 10
    let monthRowHeight: CGFloat = 14
    let gridHeight = 7 * minCellSize + 6 * cellSpacing
    let legendHeight: CGFloat = 14
    return
      monthRowHeight + Spacing.s + gridHeight + Spacing.s
      + legendHeight
  }
}

// MARK: - Inner grid view

private struct ActivityChartGrid: View {
  let grid: [[Date?]]
  let lookup: [DateComponents: Int]
  let labels: [(String, Int)]
  let cellSize: CGFloat
  let cellSpacing: CGFloat
  let dayLabelWidth: CGFloat
  let gridWidth: CGFloat
  var showLabels: Bool = true

  private let calendar = Calendar.current

  var body: some View {
    if showLabels {
      VStack(alignment: .leading, spacing: Spacing.s) {
        monthLabelsRow
        gridRow
        legendRow
      }
    } else {
      weekColumnsGrid
    }
  }

  private var monthLabelsRow: some View {
    HStack(spacing: 0) {
      Color.clear.frame(
        width: dayLabelWidth + cellSpacing, height: 14)
      ZStack(alignment: .leading) {
        Color.clear.frame(width: gridWidth, height: 14)
        ForEach(labels, id: \.1) { item in
          Text(item.0)
            .font(Typography.chartLabel)
            .foregroundStyle(WQColor.secondary)
            .offset(
              x: CGFloat(item.1) * (cellSize + cellSpacing))
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
          .frame(
            width: dayLabelWidth, height: cellSize,
            alignment: .trailing)
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
    let comps = calendar.dateComponents(
      [.year, .month, .day], from: date)
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

  private func activityLevel(for wordCount: Int?) -> Int {
    let total = wordCount ?? 0
    if total == 0 { return 0 }
    if total < 100 { return 1 }
    if total < 300 { return 2 }
    if total < 600 { return 3 }
    return 4
  }

  /// Unified monochrome color levels for both compact and full modes.
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
