import SwiftUI
import SwiftData

struct FreeWriteView: View {
    /// The real day index (used for the back-to-done transition).
    let dayIndex: Int
    let onBack: () -> Void
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var text = ""
    @FocusState private var isFocused: Bool
    /// Direct reference to the free-write entry (separate from the main day entry).
    @State private var managedEntry: DayEntry?

    private var wordCount: Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Back button row (below the global brand bar)
            HStack {
                Button(action: {
                    saveDraft()
                    onBack()
                }) {
                    Text("Back")
                        .foregroundStyle(WQColor.primary)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.contentHorizontal)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xs)

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
                        .lineSpacing(6)
                        .foregroundStyle(WQColor.primary)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .frame(minHeight: 300)
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
                .buttonStyle(WQOutlinedButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Spacing.contentHorizontal)
            .padding(.bottom, Spacing.l)
            .background(.ultraThinMaterial)
        }
        .task {
            resolveEntryAndRestoreDraft()
            // Delay focus slightly to avoid interfering with the phase transition animation
            try? await Task.sleep(nanoseconds: 600_000_000)
            isFocused = true
        }
        .onChange(of: text) { _, _ in
            saveDraft()
        }
    }

    // MARK: - Persistence

    /// Find an existing in-progress free-write entry or create a new one at a
    /// synthetic dayIndex (200_000+). This never touches the main day entry.
    /// The next available free-write index is computed locally from existing entries.
    private func resolveEntryAndRestoreDraft() {
        // Already resolved (e.g. SwiftUI re-ran .task)
        if managedEntry != nil {
            if let existingText = managedEntry?.writingText, !existingText.isEmpty {
                text = existingText
            }
            return
        }

        // Look for any in-progress free write
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate<DayEntry> {
                $0.isFreeWrite == true && $0.writingCompleted == false
            }
        )
        if let inProgress = try? modelContext.fetch(descriptor).first {
            managedEntry = inProgress
            if let existingText = inProgress.writingText, !existingText.isEmpty {
                text = existingText
            }
            return
        }

        // No in-progress free write — create a new one.
        // Compute the next available free-write index from existing entries.
        let allDescriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate<DayEntry> {
                $0.isFreeWrite == true
            }
        )
        let existingFreeWrites = (try? modelContext.fetch(allDescriptor)) ?? []
        let maxIndex = existingFreeWrites.map { $0.dayIndex }.max() ?? (DayEntry.freeWriteIndexBase - 1)
        let freeWriteIndex = maxIndex + 1

        let entry = DayEntry(dayIndex: freeWriteIndex)
        entry.isFreeWrite = true
        modelContext.insert(entry)
        do { try modelContext.save() } catch { print("FreeWriteView: save new entry failed: \(error)") }
        managedEntry = entry
    }

    /// Auto-save draft on every keystroke.
    private func saveDraft() {
        guard let entry = managedEntry else { return }
        entry.writingText = text
        entry.writingWordCount = wordCount
        do { try modelContext.save() } catch { print("FreeWriteView: saveDraft failed: \(error)") }
    }

    /// Save as completed, sync to server, and return to DoneView.
    private func completeWriting() {
        guard let entry = managedEntry else { return }

        entry.writingText = text
        entry.writingWordCount = wordCount
        entry.writingCompleted = true
        entry.readingCompleted = true // Mark as complete cycle
        entry.needsSync = true
        do { try modelContext.save() } catch { print("FreeWriteView: completeWriting save failed: \(error)") }

        // Sync to server — server resolves entry from isFreeWrite context
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
