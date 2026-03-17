import Inject
import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.betterwriter", category: "WriteView")

struct WriteView: View {
  @ObserveInjection var inject
  let dayIndex: Int
  /// The day whose reading the user is writing about.
  let aboutDayIndex: Int
  let onComplete: () -> Void

  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

  @State private var userText = ""
  @State private var prompt: String?
  @State private var promptError: String?
  @State private var isLoadingPrompt = true
  @FocusState private var isEditorFocused: Bool
  @State private var displayedPrompt = ""
  @State private var typewriter = TypewriterAnimator()
  /// Direct reference to the managed entry.
  @State private var managedEntry: DayEntry?
  /// Cached word count.
  @State private var wordCount: Int = 0
  /// Debounce task for auto-saving drafts.
  @State private var draftSaveTask: Task<Void, Never>?

  private var profile: UserProfile? { profiles.first }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.l) {
          Spacer(minLength: Spacing.xxl)

          // Prompt
          if isLoadingPrompt {
            ProgressView()
              .tint(WQColor.primary)
              .accessibilityLabel("Loading writing prompt")
              .frame(maxWidth: .infinity, alignment: .center)
          } else if !displayedPrompt.isEmpty {
            Text(displayedPrompt)
              .font(Typography.sansBody)
              .foregroundStyle(WQColor.secondary)
              .lineSpacing(Typography.promptLineSpacing)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else if let prompt = prompt {
            Text(prompt)
              .font(Typography.sansBody)
              .foregroundStyle(WQColor.secondary)
              .lineSpacing(Typography.promptLineSpacing)
          } else if let promptError {
            WQErrorView(message: promptError) {
              isLoadingPrompt = true
              self.promptError = nil
              Task { await loadPromptAndDraft() }
            }
          }

          // Text editor
          ZStack(alignment: .topLeading) {
            if userText.isEmpty {
              Text("Start writing...")
                .font(Typography.serifBody)
                .foregroundStyle(WQColor.placeholder)
                .padding(.top, Spacing.textEditorTopInset)
                .padding(.leading, Spacing.textEditorLeadingInset)
            }

            TextEditor(text: $userText)
              .font(Typography.serifBody)
              .lineSpacing(Typography.editorLineSpacing)
              .foregroundStyle(WQColor.primary)
              .scrollContentBackground(.hidden)
              .focused($isEditorFocused)
              .frame(minHeight: Spacing.textEditorMinHeight)
              .accessibilityLabel("Writing area")
              .accessibilityHint("Write your response here")
          }

          Spacer(minLength: Spacing.xxxl)
        }
        .padding(.horizontal, Spacing.contentHorizontal)
      }

      // Bottom bar: word count + done button
      VStack(spacing: Spacing.m) {
        Text("\(wordCount) words")
          .font(Typography.sansCaption)
          .foregroundStyle(WQColor.secondary)

        Button(action: completeWriting) {
          Text("DONE WRITING")
        }
        .buttonStyle(WQOutlinedButtonStyle(isFilled: true))
        .accessibilityHint("Mark your writing as complete")
        .disabled(
          userText.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty)
      }
      .padding(.horizontal, Spacing.contentHorizontal)
      .padding(.bottom, Spacing.l)
    }
    .task {
      await loadPromptAndDraft()
    }
    .onChange(of: userText) { _, newValue in
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

  // MARK: - Actions

  @MainActor
  private func resolveEntry() -> DayEntry {
    if let existing = managedEntry { return existing }

    let targetIndex = dayIndex
    let descriptor = FetchDescriptor<DayEntry>(
      predicate: #Predicate<DayEntry> {
        $0.dayIndex == targetIndex
          && $0.isFreeWrite == false
          && $0.isBonusReading == false
      }
    )
    if let fetched = try? modelContext.fetch(descriptor).first {
      managedEntry = fetched
      return fetched
    }

    let entry = DayEntry(dayIndex: dayIndex)
    modelContext.insert(entry)
    do { try modelContext.save() } catch {
      print("WriteView: save new entry failed: \(error)")
    }
    managedEntry = entry
    return entry
  }

  @MainActor
  private func loadPromptAndDraft(retried: Bool = false) async {
    let entry = resolveEntry()

    // Restore draft if exists.
    if let existingText = entry.writingText, !existingText.isEmpty {
      userText = existingText
    }

    // If prompt is already stored locally, show it immediately.
    if let existingPrompt = entry.writingPrompt {
      prompt = existingPrompt
      isLoadingPrompt = false
      return
    }

    // Concurrency guard
    let loadKey = "stream.prompt"
    let store = StreamSessionStore.shared
    guard store.beginLoad(key: loadKey) else { return }
    defer { store.endLoad(key: loadKey) }

    displayedPrompt = ""
    typewriter.cancel()

    do {
      let prefetch = PrefetchStore.shared

      switch prefetch.prompt {
      case .ready(let promptText):
        // INSTANT: Pre-fetched prompt. Save + typewriter animate.
        prompt = promptText
        let promptEntry = resolveEntry()
        promptEntry.writingPrompt = promptText
        do { try modelContext.save() } catch {
          print("WriteView: save prompt failed: \(error)")
        }
        isLoadingPrompt = false
        typewriter.enqueue(promptText, into: $displayedPrompt, fast: true)
        await typewriter.waitForCompletion()
        promptError = nil
        return

      case .streaming(let stream):
        // STREAM: Consume SSE events from pre-fetched stream.
        try await consumePromptStream(stream)
        return

      case .failed, .idle, .loading:
        // Prefetch didn't work. Do a fresh request.
        try await freshPromptRequest()
        return
      }
    } catch {
      if !retried {
        PrefetchStore.shared.prompt = .idle
        await loadPromptAndDraft(retried: true)
        return
      }
      prompt = nil
      promptError = "Couldn't load prompt."
      print("WriteView: Failed to load prompt: \(error)")
      isLoadingPrompt = false
    }
  }

  /// Consume an SSE stream of prompt events, saving the result locally.
  @MainActor
  private func consumePromptStream(
    _ stream: AsyncThrowingStream<PromptStreamEvent, Error>
  ) async throws {
    var streamedPrompt = ""
    var completedPrompt: String?

    for try await event in stream {
      switch event {
      case .start:
        break
      case .delta(let text, _):
        streamedPrompt += text
        typewriter.enqueue(text, into: $displayedPrompt)
        isLoadingPrompt = false
      case .complete(let finalPrompt, _):
        completedPrompt = finalPrompt
      case .heartbeat, .end:
        break
      case .error(let message, _):
        throw NSError(
          domain: "PromptStream", code: 500,
          userInfo: [NSLocalizedDescriptionKey: message]
        )
      }
    }

    await typewriter.waitForCompletion()

    if let finalPrompt = completedPrompt {
      prompt = finalPrompt
      displayedPrompt = ""
    } else if !streamedPrompt.trimmingCharacters(
      in: .whitespacesAndNewlines
    ).isEmpty {
      prompt = streamedPrompt
      displayedPrompt = ""
    }

    // Save prompt locally.
    let promptEntry = resolveEntry()
    promptEntry.writingPrompt = prompt
    do { try modelContext.save() } catch {
      print("WriteView: save prompt failed: \(error)")
    }

    isLoadingPrompt = false
    promptError = nil
  }

  /// Make a fresh generatePrompt() request and process the result.
  @MainActor
  private func freshPromptRequest() async throws {
    let result = try await APIClient.shared.generatePrompt()
    switch result {
    case .immediate(let event):
      if case .complete(let promptText, _) = event {
        prompt = promptText
        let promptEntry = resolveEntry()
        promptEntry.writingPrompt = promptText
        do { try modelContext.save() } catch {
          print("WriteView: save prompt failed: \(error)")
        }
        isLoadingPrompt = false
        typewriter.enqueue(promptText, into: $displayedPrompt, fast: true)
        await typewriter.waitForCompletion()
        promptError = nil
      }
    case .stream(let stream):
      try await consumePromptStream(stream)
    }
  }

  @MainActor
  private func saveDraft() {
    guard let entry = managedEntry else { return }
    entry.writingText = userText
    entry.writingWordCount = wordCount
    do { try modelContext.save() } catch {
      print("WriteView: saveDraft failed: \(error)")
    }
  }

  @MainActor
  private func completeWriting() {
    logger.info("completeWriting: START dayIndex=\(dayIndex) wordCount=\(wordCount)")
    draftSaveTask?.cancel()
    let entry = resolveEntry()
    logger.info(
      "completeWriting: entry resolved, dayIndex=\(entry.dayIndex) readingCompleted=\(entry.readingCompleted) writingCompleted=\(entry.writingCompleted)"
    )

    entry.writingText = userText
    entry.writingWordCount = wordCount
    entry.writingCompleted = true
    entry.needsSync = true
    do {
      try modelContext.save()
      logger.info("completeWriting: saved writingCompleted=true for dayIndex=\(entry.dayIndex)")
    } catch {
      logger.error("completeWriting: save FAILED: \(error.localizedDescription)")
    }

    Haptics.success()

    // Update profile stats
    if let profile = profile {
      profile.totalWordsWritten += wordCount

      if dayIndex == 0 {
        profile.onboardingDay0Done = true
      } else if dayIndex == 1 {
        profile.onboardingDay1Done = true

        Task {
          let granted =
            await NotificationService.requestAuthorization()
          if granted {
            NotificationService.scheduleDailyReminder(
              dayIndex: dayIndex)
          }
        }
      }

      let streak = DayEngine.calculateStreak(
        entries: Array(entries))
      profile.currentStreak = streak
      if streak > profile.longestStreak {
        profile.longestStreak = streak
      }

      do { try modelContext.save() } catch {
        print("WriteView: save profile stats failed: \(error)")
      }
    }

    // Sync to server
    Task {
      do {
        _ = try await APIClient.shared.updateEntry(
          fields: [
            "dayIndex": dayIndex,
            "writingText": userText,
            "writingWordCount": wordCount,
            "writingCompleted": true,
          ]
        )
      } catch {
        print("WriteView: Failed to sync writing: \(error)")
      }
    }

    logger.info("completeWriting: calling onComplete()")
    onComplete()
    logger.info("completeWriting: END")
  }
}
