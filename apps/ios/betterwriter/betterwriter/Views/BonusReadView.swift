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
  @State private var streamedBody = ""
  // Word-fade streaming state
  @State private var displayedText = ""
  @State private var pendingChunks: [String] = []
  @State private var revealTask: Task<Void, Never>?
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
            loadingView
          } else if let error = errorMessage {
            errorView(error)
          } else if !displayedText.isEmpty {
            markdownContent(text: displayedText)
          } else if let body = managedEntry?.readingBody {
            markdownContent(text: body)
          }

          Spacer(minLength: Spacing.xxxl)
        }
        .padding(.horizontal, Spacing.readingHorizontal)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if !isLoading && errorMessage == nil && managedEntry?.readingBody != nil {
        doneButton
      }
    }
    .task {
      await loadBonusReading()
    }
  }

  // MARK: - Subviews

  private func markdownContent(text: String) -> some View {
    Text(Self.markdownAttributedString(text))
      .font(Typography.serifBody)
      .lineSpacing(6)
      .foregroundStyle(WQColor.primary)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private static func markdownAttributedString(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace
    )
    return (try? AttributedString(markdown: text, options: options))
      ?? AttributedString(text)
  }

  @MainActor
  private func enqueueTypewriter(_ text: String) {
    let chunks = Self.wordChunks(from: text)
    pendingChunks.append(contentsOf: chunks)
    guard revealTask == nil || revealTask!.isCancelled else { return }
    revealTask = Task {
      while !pendingChunks.isEmpty && !Task.isCancelled {
        let chunk = pendingChunks.removeFirst()
        withAnimation(.easeIn(duration: 0.12)) {
          displayedText += chunk
        }
        let delay: UInt64 = chunk.count <= 2 ? 20_000_000 : 40_000_000
        try? await Task.sleep(nanoseconds: delay)
      }
      revealTask = nil
    }
  }

  private static func wordChunks(from text: String) -> [String] {
    guard !text.isEmpty else { return [] }
    var chunks: [String] = []
    var current = ""
    for ch in text {
      current.append(ch)
      if ch.isWhitespace && !current.trimmingCharacters(in: .whitespaces).isEmpty {
        chunks.append(current)
        current = ""
      }
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }

  private var loadingView: some View {
    VStack(spacing: Spacing.m) {
      Spacer(minLength: 200)
      ProgressView()
        .tint(WQColor.primary)
      Text("Finding something interesting to read...")
        .font(Typography.sansCaption)
        .foregroundStyle(WQColor.secondary)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private func errorView(_ message: String) -> some View {
    VStack(spacing: Spacing.m) {
      Spacer(minLength: 200)
      Text(message)
        .font(Typography.sansBody)
        .foregroundStyle(WQColor.secondary)
        .multilineTextAlignment(.center)
      Button("Try again") {
        Task { await loadBonusReading() }
      }
      .font(Typography.sansButton)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var doneButton: some View {
    Button(action: completeReading) {
      if isCompleting {
        ProgressView()
          .tint(WQColor.primary)
      } else {
        Text("DONE READING")
      }
    }
    .buttonStyle(WQOutlinedButtonStyle())
    .disabled(isCompleting)
    .padding(.horizontal, Spacing.contentHorizontal)
    .padding(.bottom, Spacing.l)
    .background(.ultraThinMaterial)
  }

  // MARK: - Actions

  /// Stream bonus reading content from server. The server decides the bonus dayIndex.
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

    // Concurrency guard — one active bonus reading load at a time.
    let guardKey = "stream.reading.bonus"
    let store = StreamSessionStore.shared
    guard store.beginLoad(key: guardKey) else { return }
    defer { store.endLoad(key: guardKey) }

    isLoading = true
    errorMessage = nil
    streamedBody = ""
    displayedText = ""
    pendingChunks = []
    revealTask?.cancel()
    revealTask = nil

    do {
      // Step 1: POST — server decides what to do.
      // No streamId sent; the server owns stream identity.
      let kickoff = try await APIClient.shared.startReadingStream()

      if kickoff.mode == "completed", let completedEntry = kickoff.entry {
        // Reading already generated — save and display without streaming.
        let localEntry = findOrCreateLocalEntry(from: completedEntry)
        localEntry.readingBody = completedEntry.readingBody ?? ""
        managedEntry = localEntry
        do { try modelContext.save() } catch {
          print("BonusReadView: save completed entry failed: \(error)")
        }
        isLoading = false
        return
      }

      // Step 2: GET — connect to the SSE stream.
      var completedEntry: APIClient.EntryResponse?
      var gotUsableStreamContent = false

      let readingEvents = await APIClient.shared.streamReading(lastEventId: nil)
      for try await event in readingEvents {
        switch event {
        case .start:
          break
        case .delta(let text, _):
          streamedBody += text
          enqueueTypewriter(text)
          isLoading = false
          gotUsableStreamContent = true
        case .complete(let entryResponse, _):
          completedEntry = entryResponse
        case .heartbeat:
          break
        case .end:
          break
        case .error(let message, _):
          throw NSError(
            domain: "BonusReadStream", code: 500,
            userInfo: [NSLocalizedDescriptionKey: message]
          )
        }
      }

      // Wait for any in-flight word-fade animation to finish.
      if let task = revealTask { await task.value }

      if let response = completedEntry {
        // Server created the entry with the bonus dayIndex.
        let localEntry = findOrCreateLocalEntry(from: response)
        localEntry.readingBody = response.readingBody ?? streamedBody
        managedEntry = localEntry
        do { try modelContext.save() } catch {
          print("BonusReadView: save reading body failed: \(error)")
        }
      } else if gotUsableStreamContent, let entry = managedEntry {
        entry.readingBody = streamedBody
        do { try modelContext.save() } catch {
          print("BonusReadView: save streamed body failed: \(error)")
        }
      } else {
        throw NSError(
          domain: "BonusReadStream", code: 500,
          userInfo: [NSLocalizedDescriptionKey: "Reading stream did not return content"]
        )
      }

      streamedBody = ""
      displayedText = ""
      isLoading = false
    } catch {
      if !retried {
        await loadBonusReading(retried: true)
        return
      }
      errorMessage = "Couldn't load the reading. Check your connection."
      isLoading = false
      print("BonusReadView: Failed to load reading: \(error)")
    }
  }

  /// Look for an existing in-progress bonus reading entry in the local store.
  @MainActor
  private func findInProgressBonusEntry() -> DayEntry? {
    let descriptor = FetchDescriptor<DayEntry>(
      predicate: #Predicate<DayEntry> {
        $0.isBonusReading == true && $0.readingCompleted == false
      }
    )
    return try? modelContext.fetch(descriptor).first
  }

  /// Create or find a local DayEntry matching the server response.
  @MainActor
  private func findOrCreateLocalEntry(from response: APIClient.EntryResponse) -> DayEntry {
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

    // Await server sync so the entity lock is released before the user
    // can request a new reading (prevents showing the old reading).
    Task {
      do {
        _ = try await APIClient.shared.updateEntry(
          fields: [
            "readingCompleted": true,
            "isBonusReading": true,
          ]
        )
      } catch {
        // Local state is correct; SyncService will retry later.
        print("BonusReadView: Failed to sync reading completion: \(error)")
      }
      onComplete()
    }
  }
}
