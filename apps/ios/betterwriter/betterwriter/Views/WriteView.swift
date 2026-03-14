import SwiftData
import SwiftUI

struct WriteView: View {
  let dayIndex: Int
  /// The day whose reading the user is writing about. Retained for state
  /// machine context; the server resolves this independently.
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
  // Word-fade streaming state
  @State private var displayedPrompt = ""
  @State private var pendingPromptChunks: [String] = []
  @State private var revealTask: Task<Void, Never>?
  /// Direct reference to the managed entry, set once via modelContext.fetch().
  /// Avoids @Query timing races that could create duplicate entries.
  @State private var managedEntry: DayEntry?
  /// Cached word count to avoid re-splitting text on every access.
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
              .lineSpacing(4)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else if let prompt = prompt {
            Text(prompt)
              .font(Typography.sansBody)
              .foregroundStyle(WQColor.secondary)
              .lineSpacing(4)
          } else if let promptError {
            VStack(spacing: Spacing.s) {
              Text(promptError)
                .font(Typography.sansCaption)
                .foregroundStyle(WQColor.secondary)
              Button("Try again") {
                isLoadingPrompt = true
                self.promptError = nil
                Task { await loadPromptAndDraft() }
              }
              .font(Typography.sansButton)
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
              .lineSpacing(6)
              .foregroundStyle(WQColor.primary)
              .scrollContentBackground(.hidden)
              .focused($isEditorFocused)
              .frame(minHeight: 300)
              .accessibilityLabel("Writing area")
              .accessibilityHint("Write your response here")
          }

          Spacer(minLength: Spacing.xxxl)
        }
        .padding(.horizontal, Spacing.contentHorizontal)
      }

      // Bottom bar: word count + done button
      VStack(spacing: Spacing.m) {
        // Word count
        Text("\(wordCount) words")
          .font(Typography.sansCaption)
          .foregroundStyle(WQColor.secondary)

        // Done button
        Button(action: completeWriting) {
          Text("DONE WRITING")
        }
        .buttonStyle(WQOutlinedButtonStyle())
        .accessibilityHint("Mark your writing as complete")
        .disabled(userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(.horizontal, Spacing.contentHorizontal)
      .padding(.bottom, Spacing.l)
      .background(.ultraThinMaterial)
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
  }

  // MARK: - Word-fade animation

  @MainActor
  private func enqueueTypewriter(_ text: String) {
    let chunks = TypewriterAnimator.wordChunks(from: text)
    pendingPromptChunks.append(contentsOf: chunks)
    guard revealTask == nil || revealTask!.isCancelled else { return }
    revealTask = Task {
      while !pendingPromptChunks.isEmpty && !Task.isCancelled {
        let chunk = pendingPromptChunks.removeFirst()
        withAnimation(.easeIn(duration: 0.12)) {
          displayedPrompt += chunk
        }
        let delay: UInt64 = chunk.count <= 2 ? 20_000_000 : 40_000_000
        try? await Task.sleep(nanoseconds: delay)
      }
      revealTask = nil
    }
  }

  // MARK: - Actions

  /// Robustly find or create the entry for this day using a synchronous fetch,
  /// avoiding the @Query timing race that could return nil right after view mount.
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
    do { try modelContext.save() } catch { print("WriteView: save new entry failed: \(error)") }
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

    // Concurrency guard: prevent duplicate in-flight loads.
    let loadKey = "stream.prompt"
    let store = StreamSessionStore.shared
    guard store.beginLoad(key: loadKey) else { return }
    defer { store.endLoad(key: loadKey) }

    var streamedPrompt = ""
    var completedPrompt: String?
    displayedPrompt = ""
    pendingPromptChunks = []
    revealTask?.cancel()
    revealTask = nil

    do {
      // Step 1: POST — server decides what to do.
      // No streamId sent; the server owns stream identity.
      let kickoff = try await APIClient.shared.startPromptStream()

      if kickoff.mode == "completed", let completedText = kickoff.prompt {
        // Prompt already generated — display without streaming.
        prompt = completedText
        let promptEntry = resolveEntry()
        promptEntry.writingPrompt = completedText
        do { try modelContext.save() } catch {
          print("WriteView: save completed prompt failed: \(error)")
        }
        isLoadingPrompt = false
        promptError = nil
        return
      }

      // Step 2: GET — connect to the SSE stream.
      let promptEvents = await APIClient.shared.streamPrompt(lastEventId: nil)
      for try await event in promptEvents {
        switch event {
        case .start:
          break
        case .delta(let text, _):
          streamedPrompt += text
          enqueueTypewriter(text)
          isLoadingPrompt = false
        case .complete(let finalPrompt, _):
          completedPrompt = finalPrompt
        case .heartbeat:
          break
        case .end:
          break
        case .error(let message, _):
          throw NSError(
            domain: "PromptStream", code: 500,
            userInfo: [NSLocalizedDescriptionKey: message]
          )
        }
      }

      // Wait for any in-flight word-fade animation to finish.
      if let task = revealTask { await task.value }

      if let finalPrompt = completedPrompt {
        prompt = finalPrompt
        displayedPrompt = ""
      } else if !streamedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        prompt = streamedPrompt
        displayedPrompt = ""
      } else if let fetched = try? await APIClient.shared.getEntry(dayIndex: dayIndex),
        let fetchedPrompt = fetched.writingPrompt,
        !fetchedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        prompt = fetchedPrompt
      } else {
        throw NSError(
          domain: "PromptStream", code: 500,
          userInfo: [NSLocalizedDescriptionKey: "Prompt stream did not return content"]
        )
      }

      // Save prompt locally.
      let promptEntry = resolveEntry()
      promptEntry.writingPrompt = prompt
      do { try modelContext.save() } catch { print("WriteView: save prompt failed: \(error)") }

      isLoadingPrompt = false
      promptError = nil
    } catch {
      if !retried {
        await loadPromptAndDraft(retried: true)
        return
      }
      prompt = nil
      promptError = "Couldn't load prompt."
      print("WriteView: Failed to load prompt: \(error)")
      isLoadingPrompt = false
    }
  }

  @MainActor
  private func saveDraft() {
    guard let entry = managedEntry else { return }
    entry.writingText = userText
    entry.writingWordCount = wordCount
    do { try modelContext.save() } catch { print("WriteView: saveDraft failed: \(error)") }
  }

  @MainActor
  private func completeWriting() {
    draftSaveTask?.cancel()
    let entry = resolveEntry()

    entry.writingText = userText
    entry.writingWordCount = wordCount
    entry.writingCompleted = true
    entry.needsSync = true
    do { try modelContext.save() } catch {
      print("WriteView: completeWriting save failed: \(error)")
    }

    // Update profile stats
    if let profile = profile {
      profile.totalWordsWritten += wordCount

      // Handle onboarding completion
      if dayIndex == 0 {
        profile.onboardingDay0Done = true
      } else if dayIndex == 1 {
        profile.onboardingDay1Done = true

        // Request notification permission after day 1
        Task {
          let granted = await NotificationService.requestAuthorization()
          if granted {
            NotificationService.scheduleDailyReminder(dayIndex: dayIndex)
          }
        }
      }

      // Update streak based on calendar days completed
      let streak = DayEngine.calculateStreak(entries: Array(entries))
      profile.currentStreak = streak
      if streak > profile.longestStreak {
        profile.longestStreak = streak
      }

      do { try modelContext.save() } catch {
        print("WriteView: save profile stats failed: \(error)")
      }
    }

    // Sync to server and store as memories — server resolves dayIndex
    Task {
      do {
        _ = try await APIClient.shared.updateEntry(
          fields: [
            "writingText": userText,
            "writingWordCount": wordCount,
            "writingCompleted": true,
          ]
        )

        // Send writing to memory system
        _ = try await APIClient.shared.sendUserInput(text: userText)
      } catch {
        print("WriteView: Failed to sync writing: \(error)")
      }
    }

    onComplete()
  }
}
