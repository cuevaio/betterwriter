import SwiftUI

struct ReadingLogView: View {
  let entries: [DayEntry]

  @State private var selectedEntry: DayEntry?

  private var readEntries: [DayEntry] {
    entries
      .filter { $0.readingCompleted && $0.readingBody != nil }
      .sorted { $0.dayIndex > $1.dayIndex }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      Text("Reading Log")
        .font(Typography.sansButton)
        .foregroundStyle(WQColor.primary)

      if readEntries.isEmpty {
        Text("No readings yet.")
          .font(Typography.sansCaption)
          .foregroundStyle(WQColor.secondary)
      } else {
        ForEach(readEntries, id: \.id) { entry in
          Button {
            selectedEntry = entry
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(Self.titleFromBody(entry.readingBody))
                  .font(Typography.sansBody)
                  .foregroundStyle(WQColor.primary)
                  .lineLimit(1)

                Text(entry.calendarDate.formatted(date: .abbreviated, time: .omitted))
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
            if let body = entry.readingBody {
              WQMarkdownContent(text: body)
            }
          }
          .padding(.horizontal, Spacing.readingHorizontal)
          .padding(.vertical, Spacing.xl)
        }
        .navigationTitle("Reading")
        .navigationBarTitleDisplayMode(.inline)
        .wqSheetToolbar { selectedEntry = nil }
      }
    }
  }

  /// Extract the display title from the first **bold** line of readingBody.
  /// The format is: first line = `**Title**`, so we strip the `**` markers.
  /// Falls back to "Untitled" if the body is nil or has no bold first line.
  static func titleFromBody(_ body: String?) -> String {
    guard let firstLine = body?.components(separatedBy: "\n").first,
      firstLine.hasPrefix("**"), firstLine.hasSuffix("**"),
      firstLine.count > 4
    else {
      return "Untitled"
    }
    return String(firstLine.dropFirst(2).dropLast(2))
  }

}
