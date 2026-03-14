import SwiftData
import SwiftUI

struct RootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.modelContext) private var modelContext

  @Query private var profiles: [UserProfile]
  @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

  @State private var currentPhase: AppPhase = .loading
  @State private var resolvedProfile: UserProfile?
  @State private var syncTask: Task<Void, Never>?
  @State private var loadingPulse = false
  @State private var lastPrefetchedDayIndex: Int?

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
          onComplete: { advanceState() }
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
          onBonusRead: {
            currentPhase = .bonusRead(dayIndex: dayIndex)
          },
          onFreeWrite: {
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
    .safeAreaInset(edge: .top) {
      HStack {
        Spacer()
        BrandWordmarkView()
        Spacer()
      }
      .padding(.top, Spacing.s)
      .padding(.bottom, Spacing.xs)
      .background(WQColor.background)
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
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        // Re-prefetch if the calendar day has advanced since last prefetch
        let currentDay = DayEngine.computeCurrentDayIndex(
          entries: Array(entries))
        if let last = lastPrefetchedDayIndex, currentDay != last {
          PrefetchStore.shared.reset()
          PrefetchStore.shared.prefetch()
          lastPrefetchedDayIndex = currentDay
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

    let resolved = DayEngine.resolveCurrentPhase(
      profile: effectiveProfile,
      entries: Array(entries)
    )
    if resolved != currentPhase {
      currentPhase = resolved
    }
  }
}
