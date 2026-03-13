import SwiftData
import SwiftUI

struct DoneView: View {
  let dayIndex: Int
  let onBonusRead: () -> Void
  let onFreeWrite: () -> Void

  @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

  @State private var showReadings = false
  @State private var showWritings = false

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
        statColumn(value: "\(streak)", label: "Streak")
        statColumn(value: "\(wordsRead)", label: "Read")
        statColumn(value: "\(wordsWritten)", label: "Written")
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, Spacing.contentHorizontal)

      Spacer()

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
          ReadingLogView(entries: Array(entries))
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
          WritingLogView(entries: Array(entries))
            .padding(.horizontal, Spacing.contentHorizontal)
            .padding(.vertical, Spacing.l)
        }
        .navigationTitle("Writings")
        .navigationBarTitleDisplayMode(.inline)
        .wqSheetToolbar { showWritings = false }
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
