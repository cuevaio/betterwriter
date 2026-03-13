import SwiftUI
import SwiftData

struct WriteView: View {
    let dayIndex: Int
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

    private var profile: UserProfile? { profiles.first }

    private var wordCount: Int {
        userText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Spacer(minLength: Spacing.xxl)

                    // Prompt
                    if isLoadingPrompt {
                        ProgressView()
                            .tint(WQColor.primary)
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
                        Text(promptError)
                            .font(Typography.sansCaption)
                            .foregroundStyle(WQColor.secondary)
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
                .disabled(userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Spacing.contentHorizontal)
            .padding(.bottom, Spacing.l)
            .background(.ultraThinMaterial)
        }
        .task {
            await loadPromptAndDraft()
        }
        .onChange(of: userText) { _, _ in
            saveDraft()
        }
    }

    // MARK: - Word-fade animation

    @MainActor
    private func enqueueTypewriter(_ text: String) {
        let chunks = Self.wordChunks(from: text)
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
    private func loadPromptAndDraft(retriedWithFreshSession: Bool = false) async {
        let entry = resolveEntry()

        // Restore draft if exists
        if let existingText = entry.writingText, !existingText.isEmpty {
            userText = existingText
        }

        // Load prompt
        if let existingPrompt = entry.writingPrompt {
            prompt = existingPrompt
            isLoadingPrompt = false
            return
        }

        // Concurrency guard: prevent duplicate loads for the same prompt
        let loadKey = "stream.prompt.\(dayIndex).\(aboutDayIndex)"
        let store = StreamSessionStore.shared
        guard store.beginLoad(key: loadKey) else { return }
        defer { store.endLoad(key: loadKey) }

        do {
            let existingSession = store.loadFreshPrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex)
            var streamId = existingSession?.streamId ?? UUID().uuidString
            var kickoffTask: Task<APIClient.StartStreamResponse, Error>?

            if existingSession == nil {
                store.savePrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex, streamId: streamId, lastEventId: nil)
                kickoffTask = Task {
                    try await APIClient.shared.startPromptStream(
                        streamId: streamId
                    )
                }
            }

        var streamedPrompt = ""
        var completedPrompt: String?
        displayedPrompt = ""
        pendingPromptChunks = []
        revealTask?.cancel()
        revealTask = nil

            // When reconnecting after the app was closed mid-stream, always
            // replay from the very beginning (cursor = nil / 0) so the full
            // prompt text is rebuilt in streamedPrompt/displayedPrompt.
            let promptEvents = await APIClient.shared.streamPrompt(
                streamId: streamId,
                lastEventId: nil
            )
            for try await event in promptEvents {
                switch event {
                case .start(let eventId):
                    if let eventId {
                        store.updatePromptCursor(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex, eventId: eventId)
                    }
                case .delta(let text, let eventId):
                    streamedPrompt += text
                    enqueueTypewriter(text)
                    isLoadingPrompt = false
                    if let eventId {
                        store.updatePromptCursor(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex, eventId: eventId)
                    }
                case .complete(let finalPrompt, let eventId):
                    completedPrompt = finalPrompt
                    if let eventId {
                        store.updatePromptCursor(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex, eventId: eventId)
                    }
                    store.clearPrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex)
                case .heartbeat(let eventId):
                    if let eventId {
                        store.updatePromptCursor(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex, eventId: eventId)
                    }
                case .end(_, let eventId):
                    if let eventId {
                        store.updatePromptCursor(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex, eventId: eventId)
                    }
                    store.clearPrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex)
                case .error(let message, let eventId):
                    if let eventId {
                        store.updatePromptCursor(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex, eventId: eventId)
                    }
                    store.clearPrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex)
                    throw NSError(domain: "PromptStream", code: 500, userInfo: [NSLocalizedDescriptionKey: message])
                }
            }

            if let kickoffTask {
                do {
                    let kickoffResponse = try await kickoffTask.value
                    // Server may return a different streamId if generation was already running
                    if kickoffResponse.streamId != streamId {
                        streamId = kickoffResponse.streamId
                        store.savePrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex, streamId: streamId, lastEventId: nil)
                    }
                } catch {
                    print("WriteView: stream kickoff failed: \(error)")
                }
            }

            // Wait for any in-flight word-fade animation to finish before
            // switching to the stable prompt string, so the text is never
            // cleared mid-animation.
            if let task = revealTask { await task.value }

            if let finalPrompt = completedPrompt {
                prompt = finalPrompt
                displayedPrompt = ""
            } else if !streamedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prompt = streamedPrompt
                displayedPrompt = ""
            } else if let fetched = try? await APIClient.shared.getEntry(dayIndex: dayIndex),
                      let fetchedPrompt = fetched.writingPrompt,
                      !fetchedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prompt = fetchedPrompt
                store.clearPrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex)
            } else {
                throw NSError(
                    domain: "PromptStream",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Prompt stream did not return a completion event"]
                )
            }

            // Save prompt locally
            let promptEntry = resolveEntry()
            promptEntry.writingPrompt = prompt
            do { try modelContext.save() } catch { print("WriteView: save prompt failed: \(error)") }

            isLoadingPrompt = false
            promptError = nil
        } catch {
            if !retriedWithFreshSession {
                // First retry: keep existing session so we reconnect to the
                // same server-side stream instead of creating a duplicate.
                await loadPromptAndDraft(retriedWithFreshSession: true)
                return
            }
            // Second failure: clear session and show error UI
            store.clearPrompt(dayIndex: dayIndex, aboutDayIndex: aboutDayIndex)
            prompt = nil
            promptError = "Couldn't load prompt. Pull to retry."
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
        let entry = resolveEntry()

        entry.writingText = userText
        entry.writingWordCount = wordCount
        entry.writingCompleted = true
        entry.needsSync = true
        do { try modelContext.save() } catch { print("WriteView: completeWriting save failed: \(error)") }

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

            do { try modelContext.save() } catch { print("WriteView: save profile stats failed: \(error)") }
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
