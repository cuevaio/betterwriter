import SwiftData
import SwiftUI

struct DoneView: View {
  let dayIndex: Int
  let onBonusRead: () -> Void
  let onFreeWrite: () -> Void

  @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

  @State private var showReadings = false
  @State private var showWritings = false

  var body: some View {
    let entryArray = Array(entries)
    let streak = DayEngine.calculateStreak(entries: entryArray)
    let wordsRead = DayEngine.totalWordsRead(entries: entryArray)
    let wordsWritten = DayEngine.totalWordsWritten(entries: entryArray)

    VStack(spacing: 0) {
      Spacer()

      // Main message
      Text("Day completed")
        .font(Typography.serifLargeTitle)
        .foregroundStyle(WQColor.primary)
        .multilineTextAlignment(.center)

      Spacer()

      // Inline stats
      HStack(spacing: Spacing.l) {
        StatColumnView(value: "\(streak)", label: "Streak")
        StatColumnView(value: "\(wordsRead)", label: "Read")
        StatColumnView(value: "\(wordsWritten)", label: "Written")
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, Spacing.contentHorizontal)

      // Activity chart
      ActivityChartView(entries: entryArray, compact: true)
        .padding(.horizontal, Spacing.contentHorizontal)
        .padding(.vertical, Spacing.l)

      // Action buttons
      VStack(spacing: Spacing.l) {
        Button(action: onBonusRead) {
          Text("Read something")
        }
        .buttonStyle(WQOutlinedButtonStyle(isSecondary: true))

        Button(action: onFreeWrite) {
          Text("Write something")
        }
        .buttonStyle(WQOutlinedButtonStyle(isSecondary: true))
      }
      .padding(.horizontal, Spacing.contentHorizontal)

      // Subtle log buttons
      HStack(spacing: Spacing.xl) {
        Button {
          showReadings = true
        } label: {
          Text("Readings")
            .font(Typography.sansCaption)
            .foregroundStyle(WQColor.secondary)
        }

        Button {
          showWritings = true
        } label: {
          Text("Writings")
            .font(Typography.sansCaption)
            .foregroundStyle(WQColor.secondary)
        }
      }
      .padding(.top, Spacing.l)
      .padding(.bottom, Spacing.xxl)
    }
    .sheet(isPresented: $showReadings) {
      NavigationStack {
        ScrollView {
          ReadingLogView(entries: entryArray)
            .padding(.horizontal, Spacing.contentHorizontal)
            .padding(.vertical, Spacing.l)
        }
        .navigationTitle("Readings")
        .navigationBarTitleDisplayMode(.inline)
        .wqSheetToolbar { showReadings = false }
      }
    }
    .sheet(isPresented: $showWritings) {
      NavigationStack {
        ScrollView {
          WritingLogView(entries: entryArray)
            .padding(.horizontal, Spacing.contentHorizontal)
            .padding(.vertical, Spacing.l)
        }
        .navigationTitle("Writings")
        .navigationBarTitleDisplayMode(.inline)
        .wqSheetToolbar { showWritings = false }
      }
    }
  }
}
