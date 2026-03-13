import SwiftData
import SwiftUI

struct ReadView: View {
  let dayIndex: Int
  let onComplete: () -> Void

  @Environment(\.openURL) private var openURL
  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var streamedBody = ""
  // Word-fade streaming state
  @State private var displayedText = ""
  @State private var pendingChunks: [String] = []
  @State private var revealTask: Task<Void, Never>?

  private var profile: UserProfile? { profiles.first }
  private var entry: DayEntry? { entries.first { $0.dayIndex == dayIndex } }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.xl) {
        Spacer(minLength: Spacing.xxl)

        if isLoading {
          loadingView
        } else if let error = errorMessage {
          errorView(error)
        } else if !displayedText.isEmpty {
          markdownContent(text: displayedText)
        } else if let entry = entry, let body = entry.readingBody {
          markdownContent(text: body)
        }

        Spacer(minLength: Spacing.xxxl)
      }
      .padding(.horizontal, Spacing.readingHorizontal)
    }
    .safeAreaInset(edge: .bottom) {
      if !isLoading && errorMessage == nil && entry?.readingBody != nil {
        doneButton
      }
    }
    .task {
      await loadReading()
    }
  }

  // MARK: - Subviews

  /// Render text as markdown using SwiftUI's built-in AttributedString.
  /// Handles bold (**), italic (*), links, code, and strikethrough.
  /// Falls back to plain text if markdown parsing fails.
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

  /// Split a delta into word-boundary chunks and enqueue them for animated reveal.
  /// Each chunk is revealed with a fade-in, giving a "words appearing" feel.
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
        // Delay between chunks: faster for short chunks (punctuation),
        // slightly longer for real words so the eye can track them.
        let delay: UInt64 = chunk.count <= 2 ? 20_000_000 : 40_000_000
        try? await Task.sleep(nanoseconds: delay)
      }
      revealTask = nil
    }
  }

  /// Split text on whitespace boundaries, keeping the trailing space attached
  /// to each word so re-joining is lossless.
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
      Text("Finding and streaming today's reading...")
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
        Task { await loadReading() }
      }
      .font(Typography.sansButton)
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var doneButton: some View {
    Button(action: completeReading) {
      Text("DONE READING")
    }
    .buttonStyle(WQOutlinedButtonStyle())
    .padding(.horizontal, Spacing.contentHorizontal)
    .padding(.bottom, Spacing.l)
    .background(.ultraThinMaterial)
  }

  // MARK: - Actions

  @MainActor
  private func loadReading(retried: Bool = false) async {
    // If we already have the reading locally, just show it.
    if entry?.readingBody != nil {
      isLoading = false
      return
    }

    // Concurrency guard: prevent duplicate in-flight loads.
    let loadKey = "stream.reading"
    let store = StreamSessionStore.shared
    guard store.beginLoad(key: loadKey) else { return }
    defer { store.endLoad(key: loadKey) }

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
        let localEntry = entry ?? DayEntry(dayIndex: completedEntry.dayIndex)
        localEntry.readingBody = completedEntry.readingBody ?? ""
        if entry == nil { modelContext.insert(localEntry) }
        try? modelContext.save()
        isLoading = false
        return
      }

      // Step 2: GET — connect to the SSE stream.
      // Server looks up the active stream for this user; no streamId query param needed.
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
            domain: "ReadStream", code: 500,
            userInfo: [NSLocalizedDescriptionKey: message]
          )
        }
      }

      // Wait for any in-flight word-fade animation to finish.
      if let task = revealTask { await task.value }

      if let response = completedEntry {
        let localEntry = entry ?? DayEntry(dayIndex: response.dayIndex)
        localEntry.readingBody = response.readingBody ?? streamedBody
        if entry == nil { modelContext.insert(localEntry) }
        try? modelContext.save()
      } else if gotUsableStreamContent {
        let localEntry = entry ?? DayEntry(dayIndex: dayIndex)
        localEntry.readingBody = streamedBody
        if entry == nil { modelContext.insert(localEntry) }
        try? modelContext.save()
      } else if let fetched = try? await APIClient.shared.getEntry(dayIndex: dayIndex),
        let fetchedBody = fetched.readingBody,
        !fetchedBody.isEmpty
      {
        let localEntry = entry ?? DayEntry(dayIndex: dayIndex)
        localEntry.readingBody = fetchedBody
        if entry == nil { modelContext.insert(localEntry) }
        try? modelContext.save()
      } else {
        throw NSError(
          domain: "ReadStream", code: 500,
          userInfo: [NSLocalizedDescriptionKey: "Reading stream did not return content"]
        )
      }

      streamedBody = ""
      displayedText = ""
      isLoading = false
    } catch {
      if !retried {
        await loadReading(retried: true)
        return
      }
      errorMessage = "Couldn't load today's reading. Check your connection."
      isLoading = false
      print("ReadView: Failed to load reading: \(error)")
    }
  }

  @MainActor
  private func completeReading() {
    guard let entry = entry else { return }
    entry.readingCompleted = true
    entry.needsSync = true
    try? modelContext.save()

    // Sync to server — server resolves which entry to update
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
