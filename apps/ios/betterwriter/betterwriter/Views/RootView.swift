import Inject
import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.betterwriter", category: "RootView")

struct RootView: View {
  @ObserveInjection var inject
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.modelContext) private var modelContext

  @Query private var profiles: [UserProfile]
  @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

  @State private var currentPhase: AppPhase = .loading
  @State private var resolvedProfile: UserProfile?
  @State private var syncTask: Task<Void, Never>?
  @State private var loadingPulse = false
  @State private var lastPrefetchedDayIndex: Int?
  @State private var animateDoneStats = false

  private var profile: UserProfile? { profiles.first }

  var body: some View {
    ZStack {
      switch currentPhase {
      case .loading:
        loadingView

      case .read(let dayIndex):
        ReadView(
          dayIndex: dayIndex, onComplete: { advanceState() }
        )
        .transition(
          .asymmetric(
            insertion: .move(edge: .trailing).combined(
              with: .opacity),
            removal: .move(edge: .leading).combined(
              with: .opacity)
          ))

      case .write(let dayIndex, let aboutDayIndex):
        WriteView(
          dayIndex: dayIndex,
          aboutDayIndex: aboutDayIndex,
          onComplete: {
            animateDoneStats = true
            advanceState()
          }
        )
        .transition(
          .asymmetric(
            insertion: .move(edge: .trailing).combined(
              with: .opacity),
            removal: .move(edge: .leading).combined(
              with: .opacity)
          ))

      case .done(let dayIndex):
        DoneView(
          dayIndex: dayIndex,
          shouldAnimateStats: animateDoneStats,
          onBonusRead: {
            animateDoneStats = false
            currentPhase = .bonusRead(dayIndex: dayIndex)
          },
          onFreeWrite: {
            animateDoneStats = false
            currentPhase = .freeWrite(dayIndex: dayIndex)
          }
        )
        .transition(
          .opacity.animation(
            .spring(response: 0.4, dampingFraction: 0.85)))

      case .bonusRead(let dayIndex):
        BonusReadView(
          dayIndex: dayIndex,
          onBack: {
            currentPhase = .done(dayIndex: dayIndex)
          },
          onComplete: {
            currentPhase = .done(dayIndex: dayIndex)
          }
        )
        .transition(
          .move(edge: .bottom).combined(with: .opacity))

      case .freeWrite(let dayIndex):
        FreeWriteView(
          dayIndex: dayIndex,
          onBack: {
            currentPhase = .done(dayIndex: dayIndex)
          },
          onComplete: {
            currentPhase = .done(dayIndex: dayIndex)
          }
        )
        .transition(
          .move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(
      .spring(response: 0.5, dampingFraction: 0.85),
      value: currentPhase
    )
    .task {
      let profile = await ensureProfile()
      resolvedProfile = profile

      // Pre-fetch both reading and prompt in parallel so views
      // have data ready immediately when the user navigates.
      PrefetchStore.shared.prefetch()
      lastPrefetchedDayIndex = DayEngine.computeCurrentDayIndex(
        entries: Array(entries))

      advanceState(profileOverride: profile)
    }
    .onChange(of: profiles) {
      if currentPhase == .loading {
        advanceState()
      }
    }
    .onChange(of: entries) {
      advanceState()
    }
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        // Re-prefetch if the calendar day has advanced since last prefetch
        let currentDay = DayEngine.computeCurrentDayIndex(
          entries: Array(entries))
        if let last = lastPrefetchedDayIndex, currentDay != last {
          PrefetchStore.shared.reset()
          PrefetchStore.shared.prefetch()
          lastPrefetchedDayIndex = currentDay
        } else if case .failed = PrefetchStore.shared.reading {
          // Previous prefetch failed (e.g. "User not found") — retry
          PrefetchStore.shared.reset()
          PrefetchStore.shared.prefetch()
        }

        advanceState()
        syncTask?.cancel()
        syncTask = Task { @MainActor in
          await SyncService.shared.syncPendingEntries(
            entries: Array(entries),
            profile: profile,
            modelContext: modelContext
          )
        }
      }
    }
    .enableInjection()
  }

  // MARK: - Loading View (wordmark removed — the safeAreaInset provides it)

  private var loadingView: some View {
    VStack(spacing: Spacing.l) {
      Spacer()
      ProgressView()
        .tint(WQColor.primary)
      Text("warming up your next page")
        .font(Typography.sansCaption)
        .foregroundStyle(WQColor.secondary)
        .opacity(loadingPulse ? 0.5 : 1.0)
        .animation(
          .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true),
          value: loadingPulse
        )
        .onAppear { loadingPulse = true }
      Spacer()
    }
  }

  // MARK: - State Management

  @discardableResult
  private func ensureProfile() async -> UserProfile {
    let descriptor = FetchDescriptor<UserProfile>()
    if let existing = try? modelContext.fetch(descriptor).first {
      return existing
    }

    let newProfile = UserProfile()
    modelContext.insert(newProfile)
    do { try modelContext.save() } catch {
      print("RootView: Failed to save new profile: \(error)")
    }

    do {
      _ = try await APIClient.shared.authenticate(
        installDate: newProfile.installDate)
    } catch {
      print("Failed to authenticate with server: \(error)")
    }

    return newProfile
  }

  private func advanceState(profileOverride: UserProfile? = nil) {
    // Don't interrupt overlay sessions
    if case .freeWrite = currentPhase { return }
    if case .bonusRead = currentPhase { return }

    let effectiveProfile =
      profileOverride ?? resolvedProfile ?? profile

    // Fetch entries directly from the model context to pick up
    // mutations that @Query hasn't propagated yet (same RunLoop tick).
    let freshEntries: [DayEntry]
    do {
      let descriptor = FetchDescriptor<DayEntry>(
        sortBy: [SortDescriptor(\DayEntry.dayIndex)]
      )
      freshEntries = try modelContext.fetch(descriptor)
      logger.info("advanceState: fetched \(freshEntries.count) entries from modelContext")
    } catch {
      freshEntries = Array(entries)
      logger.error(
        "advanceState: modelContext.fetch failed: \(error.localizedDescription), falling back to @Query (\(freshEntries.count) entries)"
      )
    }

    // Physically merge any duplicate DayEntry objects sharing the same dayIndex.
    // This can happen when ReadView and WriteView each create a new DayEntry
    // for the same dayIndex (no uniqueness constraint on the model).
    var seen: [Int: DayEntry] = [:]
    for entry in freshEntries where !entry.isSyntheticEntry {
      if let existing = seen[entry.dayIndex] {
        // Merge flags into the keeper, delete the duplicate
        if entry.readingCompleted { existing.readingCompleted = true }
        if entry.readingBody != nil && existing.readingBody == nil {
          existing.readingBody = entry.readingBody
        }
        if entry.readingBodyDraft != nil && existing.readingBodyDraft == nil {
          existing.readingBodyDraft = entry.readingBodyDraft
        }
        if entry.writingCompleted { existing.writingCompleted = true }
        if entry.writingText != nil && existing.writingText == nil {
          existing.writingText = entry.writingText
        }
        if entry.writingPrompt != nil && existing.writingPrompt == nil {
          existing.writingPrompt = entry.writingPrompt
        }
        existing.writingWordCount = max(
          existing.writingWordCount, entry.writingWordCount)
        if entry.calendarDate > existing.calendarDate {
          existing.calendarDate = entry.calendarDate
        }
        existing.needsSync = true
        modelContext.delete(entry)
        logger.warning("advanceState: deleted duplicate entry for dayIndex=\(entry.dayIndex)")
      } else {
        seen[entry.dayIndex] = entry
      }
    }
    if seen.values.contains(where: { $0.needsSync }) {
      do { try modelContext.save() } catch {
        logger.error("advanceState: failed to save after dedup: \(error.localizedDescription)")
      }
    }

    // Log entry states for debugging
    for e in freshEntries where !e.isSyntheticEntry {
      logger.info(
        "  entry[\(e.dayIndex)]: reading=\(e.readingCompleted) writing=\(e.writingCompleted) date=\(e.calendarDate.formatted(.iso8601))"
      )
    }

    let resolved = DayEngine.resolveCurrentPhase(
      profile: effectiveProfile,
      entries: freshEntries
    )
    logger.info(
      "advanceState: current=\(String(describing: currentPhase)) resolved=\(String(describing: resolved))"
    )
    if resolved != currentPhase {
      logger.info(
        "advanceState: transitioning \(String(describing: currentPhase)) -> \(String(describing: resolved))"
      )
      currentPhase = resolved
    } else {
      logger.info("advanceState: no change, staying at \(String(describing: currentPhase))")
    }
  }
}
