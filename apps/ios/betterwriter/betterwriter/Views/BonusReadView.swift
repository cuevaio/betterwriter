import SwiftData
import SwiftUI

struct BonusReadView: View {
  /// The real day index (used for the back-to-done transition).
  let dayIndex: Int
  let onBack: () -> Void
  let onComplete: () -> Void

  @Environment(\.modelContext) private var modelContext

  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var displayedText = ""
  @State private var typewriter = TypewriterAnimator()
  /// Direct reference to the bonus reading entry.
  @State private var managedEntry: DayEntry?
  @State private var isCompleting = false

  var body: some View {
    VStack(spacing: 0) {
      WQBackButton(action: onBack)

      // Reading content
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.xl) {
          Spacer(minLength: Spacing.m)

          if isLoading {
            WQLoadingView(
              caption: "Finding something interesting to read...")
          } else if let error = errorMessage {
            WQErrorView(message: error) {
              Task { await loadBonusReading() }
            }
          } else if !displayedText.isEmpty {
            WQMarkdownContent(text: displayedText)
          } else if let body = managedEntry?.readingBody {
            WQMarkdownContent(text: body)
          }

          Spacer(minLength: Spacing.xxxl)
        }
        .padding(.horizontal, Spacing.readingHorizontal)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if !isLoading && errorMessage == nil
        && managedEntry?.readingBody != nil
      {
        doneButton
      }
    }
    .task {
      await loadBonusReading()
    }
  }

  // MARK: - Subviews

  private var doneButton: some View {
    Button(action: completeReading) {
      if isCompleting {
        ProgressView()
          .tint(WQColor.primary)
      } else {
        Text("DONE READING")
      }
    }
    .buttonStyle(WQOutlinedButtonStyle(isFilled: true))
    .accessibilityHint("Mark this bonus reading as complete")
    .disabled(isCompleting)
    .padding(.horizontal, Spacing.contentHorizontal)
    .padding(.bottom, Spacing.l)
    .background(
      WQColor.background.opacity(0.9)
        .background(.ultraThinMaterial)
    )
  }

  // MARK: - Actions

  /// Stream bonus reading content from server.
  @MainActor
  private func loadBonusReading(retried: Bool = false) async {
    // Check for an existing in-progress bonus entry with content.
    if let existing = findInProgressBonusEntry() {
      managedEntry = existing
      if existing.readingBody != nil {
        isLoading = false
        return
      }
    }

    // Concurrency guard
    let guardKey = "stream.reading.bonus"
    let store = StreamSessionStore.shared
    guard store.beginLoad(key: guardKey) else { return }
    defer { store.endLoad(key: guardKey) }

    isLoading = true
    errorMessage = nil
    displayedText = ""
    typewriter.cancel()

    do {
      let result = try await APIClient.shared.generateReading()

      switch result {
      case .immediate(let event):
        if case .complete(let entryResponse, _) = event {
          let localEntry = findOrCreateLocalEntry(from: entryResponse)
          localEntry.readingBody = entryResponse.readingBody ?? ""
          managedEntry = localEntry
          do { try modelContext.save() } catch {
            print("BonusReadView: save completed entry failed: \(error)")
          }
          if let body = entryResponse.readingBody, !body.isEmpty {
            isLoading = false
            typewriter.enqueue(body, into: $displayedText, fast: true)
            await typewriter.waitForCompletion()
          }
          isLoading = false
        }

      case .stream(let stream):
        var completedEntry: APIClient.EntryResponse?
        var streamedBody = ""

        for try await event in stream {
          switch event {
          case .start:
            break
          case .delta(let text, _):
            streamedBody += text
            typewriter.enqueue(text, into: $displayedText)
            isLoading = false
          case .complete(let entryResponse, _):
            completedEntry = entryResponse
          case .heartbeat, .end:
            break
          case .error(let message, _):
            throw NSError(
              domain: "BonusReadStream", code: 500,
              userInfo: [NSLocalizedDescriptionKey: message]
            )
          }
        }

        await typewriter.waitForCompletion()

        if let response = completedEntry {
          let localEntry = findOrCreateLocalEntry(from: response)
          localEntry.readingBody = response.readingBody ?? streamedBody
          managedEntry = localEntry
          do { try modelContext.save() } catch {
            print("BonusReadView: save reading body failed: \(error)")
          }
        } else if !streamedBody.isEmpty, let entry = managedEntry {
          entry.readingBody = streamedBody
          do { try modelContext.save() } catch {
            print("BonusReadView: save streamed body failed: \(error)")
          }
        } else {
          throw NSError(
            domain: "BonusReadStream", code: 500,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Reading stream did not return content"
            ]
          )
        }
      }

      isLoading = false
    } catch {
      if !retried {
        await loadBonusReading(retried: true)
        return
      }
      errorMessage =
        "Couldn't load the reading. Check your connection."
      isLoading = false
      print("BonusReadView: Failed to load reading: \(error)")
    }
  }

  @MainActor
  private func findInProgressBonusEntry() -> DayEntry? {
    let descriptor = FetchDescriptor<DayEntry>(
      predicate: #Predicate<DayEntry> {
        $0.isBonusReading == true && $0.readingCompleted == false
      }
    )
    return try? modelContext.fetch(descriptor).first
  }

  @MainActor
  private func findOrCreateLocalEntry(
    from response: APIClient.EntryResponse
  ) -> DayEntry {
    let targetIndex = response.dayIndex
    let descriptor = FetchDescriptor<DayEntry>(
      predicate: #Predicate<DayEntry> {
        $0.dayIndex == targetIndex
      }
    )
    if let existing = try? modelContext.fetch(descriptor).first {
      return existing
    }

    let entry = DayEntry(dayIndex: response.dayIndex)
    entry.isBonusReading = true
    modelContext.insert(entry)
    return entry
  }

  @MainActor
  private func completeReading() {
    guard let entry = managedEntry, !isCompleting else { return }
    isCompleting = true

    entry.readingCompleted = true
    entry.needsSync = true
    do { try modelContext.save() } catch {
      print("BonusReadView: save completion failed: \(error)")
    }

    Haptics.medium()

    Task {
      do {
        _ = try await APIClient.shared.updateEntry(
          fields: [
            "readingCompleted": true,
            "isBonusReading": true,
          ]
        )
      } catch {
        print(
          "BonusReadView: Failed to sync reading completion: \(error)"
        )
      }
      onComplete()
    }
  }
}
