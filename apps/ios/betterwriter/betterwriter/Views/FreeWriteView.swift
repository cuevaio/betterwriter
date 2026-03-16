import Inject
import SwiftData
import SwiftUI

struct FreeWriteView: View {
  @ObserveInjection var inject
  /// The real day index (used for the back-to-done transition).
  let dayIndex: Int
  let onBack: () -> Void
  let onComplete: () -> Void

  @Environment(\.modelContext) private var modelContext

  @State private var text = ""
  @FocusState private var isFocused: Bool
  /// Direct reference to the free-write entry.
  @State private var managedEntry: DayEntry?
  /// Cached word count.
  @State private var wordCount: Int = 0
  /// Debounce task for auto-saving drafts.
  @State private var draftSaveTask: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 0) {
      WQBackButton {
        draftSaveTask?.cancel()
        saveDraft()
        onBack()
      }

      // Text editor
      ScrollView {
        ZStack(alignment: .topLeading) {
          if text.isEmpty {
            Text("Write whatever you want...")
              .font(Typography.serifBody)
              .foregroundStyle(WQColor.placeholder)
              .padding(.top, Spacing.textEditorTopInset)
              .padding(.leading, Spacing.textEditorLeadingInset)
          }

          TextEditor(text: $text)
            .font(Typography.serifBody)
            .lineSpacing(Typography.editorLineSpacing)
            .foregroundStyle(WQColor.primary)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .frame(minHeight: Spacing.textEditorMinHeight)
            .accessibilityLabel("Free writing area")
            .accessibilityHint("Write whatever you want")
        }
        .padding(.horizontal, Spacing.contentHorizontal)
        .padding(.top, Spacing.m)
      }

      // Bottom bar: word count + done button
      VStack(spacing: Spacing.m) {
        Text("\(wordCount) words")
          .font(Typography.sansCaption)
          .foregroundStyle(WQColor.secondary)

        Button(action: completeWriting) {
          Text("DONE")
        }
        .buttonStyle(WQOutlinedButtonStyle(isFilled: true))
        .disabled(
          text.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty)
      }
      .padding(.horizontal, Spacing.contentHorizontal)
      .padding(.bottom, Spacing.l)
      .background(
        WQColor.background.opacity(0.9)
          .background(.ultraThinMaterial)
      )
    }
    .task {
      resolveEntryAndRestoreDraft()
      try? await Task.sleep(nanoseconds: Spacing.focusDelayNs)
      isFocused = true
    }
    .onChange(of: text) { _, newValue in
      wordCount =
        newValue.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }.count
      draftSaveTask?.cancel()
      draftSaveTask = Task {
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        saveDraft()
      }
    }
    .enableInjection()
  }

  // MARK: - Persistence

  private func resolveEntryAndRestoreDraft() {
    if managedEntry != nil {
      if let existingText = managedEntry?.writingText,
        !existingText.isEmpty
      {
        text = existingText
      }
      return
    }

    let descriptor = FetchDescriptor<DayEntry>(
      predicate: #Predicate<DayEntry> {
        $0.isFreeWrite == true && $0.writingCompleted == false
      }
    )
    if let inProgress = try? modelContext.fetch(descriptor).first {
      managedEntry = inProgress
      if let existingText = inProgress.writingText,
        !existingText.isEmpty
      {
        text = existingText
      }
      return
    }

    let allDescriptor = FetchDescriptor<DayEntry>(
      predicate: #Predicate<DayEntry> {
        $0.isFreeWrite == true
      }
    )
    let existingFreeWrites =
      (try? modelContext.fetch(allDescriptor)) ?? []
    let maxIndex =
      existingFreeWrites.map { $0.dayIndex }.max()
      ?? (DayEntry.freeWriteIndexBase - 1)
    let freeWriteIndex = maxIndex + 1

    let entry = DayEntry(dayIndex: freeWriteIndex)
    entry.isFreeWrite = true
    modelContext.insert(entry)
    do { try modelContext.save() } catch {
      print("FreeWriteView: save new entry failed: \(error)")
    }
    managedEntry = entry
  }

  private func saveDraft() {
    guard let entry = managedEntry else { return }
    entry.writingText = text
    entry.writingWordCount = wordCount
    do { try modelContext.save() } catch {
      print("FreeWriteView: saveDraft failed: \(error)")
    }
  }

  private func completeWriting() {
    guard let entry = managedEntry else { return }

    entry.writingText = text
    entry.writingWordCount = wordCount
    entry.writingCompleted = true
    entry.readingCompleted = true
    entry.needsSync = true
    do { try modelContext.save() } catch {
      print("FreeWriteView: completeWriting save failed: \(error)")
    }

    Haptics.medium()

    Task {
      do {
        _ = try await APIClient.shared.updateEntry(
          fields: [
            "writingText": text,
            "writingWordCount": wordCount,
            "writingCompleted": true,
            "isFreeWrite": true,
          ]
        )
      } catch {
        print("FreeWriteView: Sync failed: \(error)")
      }
    }

    onComplete()
  }
}
