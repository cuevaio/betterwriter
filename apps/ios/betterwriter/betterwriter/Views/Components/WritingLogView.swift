import SwiftUI

struct WritingLogView: View {
  let entries: [DayEntry]

  @State private var selectedEntry: DayEntry?

  private var writtenEntries: [DayEntry] {
    entries
      .filter { $0.writingCompleted && $0.writingText != nil }
      .sorted { $0.dayIndex > $1.dayIndex }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      Text("Writing Log")
        .font(Typography.sansButton)
        .foregroundStyle(WQColor.primary)

      if writtenEntries.isEmpty {
        Text("No writing yet.")
          .font(Typography.sansCaption)
          .foregroundStyle(WQColor.secondary)
      } else {
        ForEach(writtenEntries, id: \.id) { entry in
          Button {
            selectedEntry = entry
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(entry.writingPrompt ?? (entry.isFreeWrite ? "Free write" : "Writing"))
                  .font(Typography.sansBody)
                  .foregroundStyle(WQColor.primary)
                  .lineLimit(1)

                HStack(spacing: Spacing.s) {
                  Text(entry.calendarDate.formatted(date: .abbreviated, time: .omitted))
                  Text("\(entry.writingWordCount) words")
                }
                .font(Typography.sansCaption)
                .foregroundStyle(WQColor.secondary)
              }
              Spacer()
            }
            .padding(.vertical, Spacing.s)
          }
        }
      }
    }
    .sheet(item: $selectedEntry) { entry in
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: Spacing.l) {
            if let prompt = entry.writingPrompt {
              Text(prompt)
                .font(Typography.sansBody)
                .foregroundStyle(WQColor.secondary)
            }
            if let text = entry.writingText {
              Text(text)
                .font(Typography.serifBody)
                .lineSpacing(6)
            }
          }
          .padding(.horizontal, Spacing.contentHorizontal)
          .padding(.vertical, Spacing.xl)
        }
        .navigationTitle("\(entry.writingWordCount) words")
        .navigationBarTitleDisplayMode(.inline)
        .wqSheetToolbar { selectedEntry = nil }
      }
    }
  }
}
