import SwiftData
import SwiftUI

struct DoneView: View {
  let dayIndex: Int
  let shouldAnimateStats: Bool
  let onBonusRead: () -> Void
  let onFreeWrite: () -> Void

  @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

  @State private var showReadings = false
  @State private var showWritings = false
  @State private var animateStats = false

  var body: some View {
    let entryArray = Array(entries)
    let streak = DayEngine.calculateStreak(entries: entryArray)
    let wordsRead = DayEngine.totalWordsRead(entries: entryArray)
    let wordsWritten = DayEngine.totalWordsWritten(
      entries: entryArray)
    let isNewUser =
      entryArray.filter {
        $0.writingCompleted && !$0.isFreeWrite
          && !$0.isBonusReading
      }.isEmpty

    ScrollView {
      VStack(spacing: 0) {
        Spacer(minLength: Spacing.xxxl)

        // Hero message
        Text(isNewUser ? "Welcome" : "Day completed")
          .font(Typography.serifLargeTitle)
          .foregroundStyle(WQColor.primary)
          .multilineTextAlignment(.center)
          .padding(.bottom, Spacing.xxl)

        // Stats row with animated counters
        if !isNewUser {
          HStack(spacing: Spacing.l) {
            AnimatedStatColumn(
              targetValue: streak,
              label: "Streak",
              symbolName: "flame",
              animate: $animateStats,
              skipAnimation: !shouldAnimateStats
            )
            AnimatedStatColumn(
              targetValue: wordsRead,
              label: "Read",
              symbolName: "book",
              animate: $animateStats,
              skipAnimation: !shouldAnimateStats
            )
            AnimatedStatColumn(
              targetValue: wordsWritten,
              label: "Written",
              symbolName: "pencil.line",
              animate: $animateStats,
              skipAnimation: !shouldAnimateStats
            )
          }
          .frame(maxWidth: .infinity)
          .padding(.horizontal, Spacing.contentHorizontal)
          .padding(.bottom, Spacing.l)
        }

        // Activity chart
        ActivityChartView(entries: entryArray, compact: true)
          .padding(.horizontal, Spacing.contentHorizontal)
          .padding(.bottom, Spacing.xl)

        // Empty state for new users
        if isNewUser {
          VStack(spacing: Spacing.s) {
            Text("Complete your first reading and writing")
            Text("to see your stats here.")
          }
          .font(Typography.sansCaption)
          .foregroundStyle(WQColor.secondary)
          .multilineTextAlignment(.center)
          .padding(.bottom, Spacing.xl)
        }

        // Action buttons with SF Symbols
        VStack(spacing: Spacing.m) {
          Button(action: {
            Haptics.light()
            onBonusRead()
          }) {
            Label("Read something", systemImage: "book.pages")
          }
          .buttonStyle(WQOutlinedButtonStyle(isSecondary: true))

          Button(action: {
            Haptics.light()
            onFreeWrite()
          }) {
            Label(
              "Write something", systemImage: "pencil.line")
          }
          .buttonStyle(WQOutlinedButtonStyle(isSecondary: true))
        }
        .padding(.horizontal, Spacing.contentHorizontal)
        .padding(.bottom, Spacing.l)

        // Subtle log links
        HStack(spacing: Spacing.xl) {
          Button {
            showReadings = true
          } label: {
            Label("Readings", systemImage: "list.bullet")
              .font(Typography.sansCaption)
              .foregroundStyle(WQColor.secondary)
          }

          Button {
            showWritings = true
          } label: {
            Label("Writings", systemImage: "list.bullet")
              .font(Typography.sansCaption)
              .foregroundStyle(WQColor.secondary)
          }
        }
        .padding(.bottom, Spacing.xxl)
      }
    }
    .onAppear {
      if shouldAnimateStats {
        // Delay stat animation to after the phase transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
          animateStats = true
        }
      } else {
        // Show stats at their actual values immediately
        animateStats = true
      }
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
