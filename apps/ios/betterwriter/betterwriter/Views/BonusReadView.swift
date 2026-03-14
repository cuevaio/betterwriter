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
  @State private var streamComplete = false
  @State private var draftSaveTask: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 0) {
      WQBackButton(action: onBack)

      // Reading content
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.xl) {
          Spacer(minLength: Spacing.m)

          if isLoading && displayedText.isEmpty {
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
      if !isLoading && errorMessage == nil && streamComplete {
        doneButton
      }
    }
    .task {
      if managedEntry?.readingBody != nil {
        streamComplete = true
      }
      await loadBonusReading()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.didBecomeActiveNotification)
    ) { _ in
      if errorMessage != nil {
        Task { await loadBonusReading() }
      } else if !streamComplete && managedEntry?.readingBody == nil
        && (managedEntry?.readingBodyDraft != nil
          || !displayedText.isEmpty)
      {
        // Stream was interrupted — save current text as draft and reconnect
        if !displayedText.isEmpty, let entry = managedEntry {
          entry.readingBodyDraft = displayedText
          do { try modelContext.save() } catch {
            print("BonusReadView: Failed to save draft on foreground: \(error)")
          }
        }
        Task { await loadBonusReading() }
      }
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
    // STEP 0: Check for an existing in-progress bonus entry with content.
    if let existing = findInProgressBonusEntry() {
      managedEntry = existing
      if existing.readingBody != nil {
        displayedText = existing.readingBody!
        streamComplete = true
        isLoading = false
        return
      }
      // STEP 1: Restore draft text immediately (no spinner).
      if let draft = existing.readingBodyDraft, !draft.isEmpty {
        displayedText = draft
        isLoading = false
      }
    }

    // Concurrency guard
    let guardKey = "stream.reading.bonus"
    let store = StreamSessionStore.shared
    guard store.beginLoad(key: guardKey) else { return }
    defer { store.endLoad(key: guardKey) }

    errorMessage = nil

    // Only reset UI if we have no draft to show
    if displayedText.isEmpty {
      isLoading = true
      typewriter.cancel()
    }

    do {
      let result = try await APIClient.shared.generateReading()

      switch result {
      case .immediate(let event):
        if case .complete(let entryResponse, _) = event {
          let localEntry = findOrCreateLocalEntry(from: entryResponse)
          localEntry.readingBody = entryResponse.readingBody ?? ""
          localEntry.readingBodyDraft = nil
          managedEntry = localEntry
          do { try modelContext.save() } catch {
            print("BonusReadView: save completed entry failed: \(error)")
          }
          if let body = entryResponse.readingBody, !body.isEmpty {
            isLoading = false
            displayedText = ""
            typewriter.cancel()
            typewriter.enqueue(body, into: $displayedText, fast: true)
            await typewriter.waitForCompletion()
          }
          streamComplete = true
          isLoading = false
        }

      case .stream(let stream):
        var completedEntry: APIClient.EntryResponse?
        var streamedBody = ""
        var deltaCount = 0

        // Catch-up state
        let resumeLength = displayedText.count
        var catchingUp = resumeLength > 0

        for try await event in stream {
          switch event {
          case .start:
            break

          case .delta(let text, _):
            streamedBody += text

            if catchingUp {
              if streamedBody.count <= resumeLength {
                continue
              }
              catchingUp = false
              let overlapInDelta = max(
                0, resumeLength - (streamedBody.count - text.count))
              let newText = String(text.dropFirst(overlapInDelta))
              if !newText.isEmpty {
                typewriter.enqueue(newText, into: $displayedText)
              }
            } else {
              typewriter.enqueue(text, into: $displayedText)
            }

            isLoading = false
            deltaCount += 1

            // Debounced draft save every 20 deltas
            if deltaCount % 20 == 0, let entry = managedEntry {
              scheduleDraftSave(body: streamedBody, entry: entry)
            }

          case .complete(let entryResponse, _):
            completedEntry = entryResponse

          case .heartbeat, .end:
            break

          case .error(let message, _):
            // Save draft before throwing
            if let entry = managedEntry {
              entry.readingBodyDraft = streamedBody
              do { try modelContext.save() } catch {
                print("BonusReadView: Failed to save draft: \(error)")
              }
            }
            throw NSError(
              domain: "BonusReadStream", code: 500,
              userInfo: [NSLocalizedDescriptionKey: message]
            )
          }
        }

        // Cancel any pending draft save
        draftSaveTask?.cancel()
        draftSaveTask = nil

        await typewriter.waitForCompletion()

        if let response = completedEntry {
          let localEntry = findOrCreateLocalEntry(from: response)
          localEntry.readingBody = response.readingBody ?? streamedBody
          localEntry.readingBodyDraft = nil
          managedEntry = localEntry
          do { try modelContext.save() } catch {
            print("BonusReadView: save reading body failed: \(error)")
          }
        } else if !streamedBody.isEmpty, let entry = managedEntry {
          entry.readingBody = streamedBody
          entry.readingBodyDraft = nil
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

        streamComplete = true
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

  // MARK: - Draft persistence

  /// Schedule a debounced draft save.
  @MainActor
  private func scheduleDraftSave(body: String, entry: DayEntry) {
    draftSaveTask?.cancel()
    draftSaveTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled else { return }
      entry.readingBodyDraft = body
      do { try modelContext.save() } catch {
        print("BonusReadView: Failed to save draft: \(error)")
      }
    }
  }

  // MARK: - Helpers

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
