import SwiftData
import SwiftUI

struct ReadView: View {
  let dayIndex: Int
  let onComplete: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var displayedText = ""
  @State private var typewriter = TypewriterAnimator()
  @State private var streamComplete = false
  @State private var draftSaveTask: Task<Void, Never>?

  private var profile: UserProfile? { profiles.first }
  private var entry: DayEntry? { entries.first { $0.dayIndex == dayIndex } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.xl) {
        Spacer(minLength: Spacing.xxl)

        if isLoading && displayedText.isEmpty {
          WQLoadingView(
            caption: "Finding and streaming today's reading...")
        } else if let error = errorMessage {
          WQErrorView(message: error) {
            Task { await loadReading() }
          }
        } else if !displayedText.isEmpty {
          WQMarkdownContent(text: displayedText)
        } else if let entry = entry, let body = entry.readingBody {
          WQMarkdownContent(text: body)
        }

        Spacer(minLength: Spacing.xxxl)
      }
      .padding(.horizontal, Spacing.readingHorizontal)
    }
    .safeAreaInset(edge: .bottom) {
      if !isLoading && errorMessage == nil && streamComplete {
        doneButton
      }
    }
    .task {
      if entry?.readingBody != nil {
        streamComplete = true
      }
      await loadReading()
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.didBecomeActiveNotification)
    ) { _ in
      if errorMessage != nil {
        Task { await loadReading() }
      } else if !streamComplete && entry?.readingBody == nil
        && (entry?.readingBodyDraft != nil || !displayedText.isEmpty)
      {
        // Stream was interrupted — save current text as draft and reconnect
        if !displayedText.isEmpty {
          saveDraftImmediately(body: displayedText)
        }
        PrefetchStore.shared.reading = .idle
        Task { await loadReading() }
      }
    }
  }

  // MARK: - Subviews

  private var doneButton: some View {
    Button(action: completeReading) {
      Text("DONE READING")
    }
    .buttonStyle(WQOutlinedButtonStyle(isFilled: true))
    .accessibilityHint("Mark today's reading as complete")
    .padding(.horizontal, Spacing.contentHorizontal)
    .padding(.bottom, Spacing.l)
    .background(
      WQColor.background.opacity(0.9)
        .background(.ultraThinMaterial)
    )
  }

  // MARK: - Actions

  @MainActor
  private func loadReading(retried: Bool = false) async {
    // STEP 0: If we already have the FINAL reading locally, show it.
    if let entry = entry, let body = entry.readingBody {
      displayedText = body
      streamComplete = true
      isLoading = false
      return
    }

    // STEP 1: Restore draft text immediately (no spinner).
    if let entry = entry, let draft = entry.readingBodyDraft, !draft.isEmpty {
      displayedText = draft
      isLoading = false
    }

    // Concurrency guard: prevent duplicate in-flight loads.
    let loadKey = "stream.reading"
    let store = StreamSessionStore.shared
    guard store.beginLoad(key: loadKey) else { return }
    defer { store.endLoad(key: loadKey) }

    errorMessage = nil

    // Only reset UI if we have no draft to show
    if displayedText.isEmpty {
      isLoading = true
      typewriter.cancel()
    }

    do {
      let prefetch = PrefetchStore.shared

      switch prefetch.reading {
      case .ready(let entryResponse):
        // INSTANT: Data was pre-fetched as JSON. Save + typewriter animate.
        saveReadingLocally(
          body: entryResponse.readingBody ?? "",
          dayIndex: entryResponse.dayIndex
        )
        if let body = entryResponse.readingBody, !body.isEmpty {
          isLoading = false
          displayedText = ""
          typewriter.cancel()
          typewriter.enqueue(body, into: $displayedText, fast: true)
          await typewriter.waitForCompletion()
        }
        streamComplete = true
        isLoading = false
        return

      case .streaming(let stream):
        // STREAM: Consume SSE events from pre-fetched stream.
        try await consumeReadingStream(stream)
        return

      case .failed, .idle, .loading:
        // Prefetch didn't work. Do a fresh request.
        try await freshReadingRequest()
        return
      }
    } catch {
      if !retried {
        PrefetchStore.shared.reading = .idle
        await loadReading(retried: true)
        return
      }
      errorMessage =
        "Couldn't load today's reading. Check your connection."
      isLoading = false
      print("ReadView: Failed to load reading: \(error)")
    }
  }

  /// Consume an SSE stream of reading events, saving the result locally.
  @MainActor
  private func consumeReadingStream(
    _ stream: AsyncThrowingStream<ReadingStreamEvent, Error>
  ) async throws {
    var completedEntry: APIClient.EntryResponse?
    var streamedBody = ""
    var deltaCount = 0

    // Catch-up state: how much text the user has already seen (from draft)
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
            // Still replaying known text — skip typewriter
            continue
          }
          // First delta that takes us past the resume point
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
        if deltaCount % 20 == 0 {
          scheduleDraftSave(body: streamedBody)
        }

      case .complete(let entry, _):
        completedEntry = entry

      case .heartbeat, .end:
        break

      case .error(let message, _):
        // Save draft before throwing so progress is preserved
        saveDraftImmediately(body: streamedBody)
        throw NSError(
          domain: "ReadStream", code: 500,
          userInfo: [NSLocalizedDescriptionKey: message]
        )
      }
    }

    // Cancel any pending draft save — we'll do a final save
    draftSaveTask?.cancel()
    draftSaveTask = nil

    await typewriter.waitForCompletion()

    if let response = completedEntry {
      saveReadingLocally(
        body: response.readingBody ?? streamedBody,
        dayIndex: response.dayIndex
      )
    } else if !streamedBody.isEmpty {
      saveReadingLocally(body: streamedBody, dayIndex: dayIndex)
    }

    streamComplete = true
    isLoading = false
  }

  /// Make a fresh generateReading() request and process the result.
  @MainActor
  private func freshReadingRequest() async throws {
    let result = try await APIClient.shared.generateReading()
    switch result {
    case .immediate(let event):
      if case .complete(let entryResponse, _) = event {
        saveReadingLocally(
          body: entryResponse.readingBody ?? "",
          dayIndex: entryResponse.dayIndex
        )
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
      try await consumeReadingStream(stream)
    }
  }

  // MARK: - Draft persistence

  /// Schedule a debounced draft save (coalesces rapid delta bursts).
  @MainActor
  private func scheduleDraftSave(body: String) {
    draftSaveTask?.cancel()
    draftSaveTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled else { return }
      saveDraftImmediately(body: body)
    }
  }

  /// Save draft text to SwiftData immediately.
  @MainActor
  private func saveDraftImmediately(body: String) {
    guard !body.isEmpty else { return }
    let localEntry = entry ?? DayEntry(dayIndex: dayIndex)
    localEntry.readingBodyDraft = body
    if entry == nil { modelContext.insert(localEntry) }
    do { try modelContext.save() } catch {
      print("ReadView: Failed to save draft: \(error)")
    }
  }

  /// Save readingBody to the local SwiftData entry and clear draft.
  @MainActor
  private func saveReadingLocally(body: String, dayIndex: Int) {
    let localEntry = entry ?? DayEntry(dayIndex: dayIndex)
    localEntry.readingBody = body
    localEntry.readingBodyDraft = nil
    if entry == nil { modelContext.insert(localEntry) }
    do { try modelContext.save() } catch {
      print("ReadView: Failed to save reading locally: \(error)")
    }
  }

  @MainActor
  private func completeReading() {
    guard let entry = entry else { return }
    entry.readingCompleted = true
    entry.needsSync = true
    do { try modelContext.save() } catch {
      print("ReadView: Failed to save reading completion: \(error)")
    }

    Haptics.medium()

    Task {
      do {
        _ = try await APIClient.shared.updateEntry(
          fields: ["readingCompleted": true]
        )
      } catch {
        print("ReadView: Failed to sync reading completion: \(error)")
      }
    }

    onComplete()
  }
}
