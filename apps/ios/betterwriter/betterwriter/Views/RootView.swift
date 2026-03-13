import SwiftData
import SwiftUI

struct RootView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.modelContext) private var modelContext

  @Query private var profiles: [UserProfile]
  @Query(sort: \DayEntry.dayIndex) private var entries: [DayEntry]

  @State private var currentPhase: AppPhase = .loading

  private var profile: UserProfile? { profiles.first }

  var body: some View {
    ZStack {
      switch currentPhase {
      case .loading:
        loadingView

      case .read(let dayIndex):
        ReadView(dayIndex: dayIndex, onComplete: { advanceState() })
          .transition(
            .asymmetric(
              insertion: .opacity.combined(with: .move(edge: .trailing)),
              removal: .opacity.combined(with: .move(edge: .leading))
            ))

      case .write(let dayIndex, let aboutDayIndex):
        WriteView(
          dayIndex: dayIndex,
          aboutDayIndex: aboutDayIndex,
          onComplete: { advanceState() }
        )
        .transition(
          .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
          ))

      case .done(let dayIndex):
        DoneView(
          dayIndex: dayIndex,
          onBonusRead: { currentPhase = .bonusRead(dayIndex: dayIndex) },
          onFreeWrite: { currentPhase = .freeWrite(dayIndex: dayIndex) }
        )
        .transition(.opacity)

      case .bonusRead(let dayIndex):
        BonusReadView(
          dayIndex: dayIndex,
          onBack: { currentPhase = .done(dayIndex: dayIndex) },
          onComplete: { currentPhase = .done(dayIndex: dayIndex) }
        )
        .transition(.opacity)

      case .freeWrite(let dayIndex):
        FreeWriteView(
          dayIndex: dayIndex,
          onBack: { currentPhase = .done(dayIndex: dayIndex) },
          onComplete: { currentPhase = .done(dayIndex: dayIndex) }
        )
        .transition(.opacity)
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
    .animation(.easeInOut(duration: 0.5), value: currentPhase)
    .onAppear {
      let profile = ensureProfile()
      advanceState(profileOverride: profile)
    }
    // Re-evaluate whenever SwiftData queries update (profiles loads asynchronously)
    .onChange(of: profiles) {
      if currentPhase == .loading {
        let profile = ensureProfile()
        advanceState(profileOverride: profile)
      }
    }
    .onChange(of: scenePhase) {
      if scenePhase == .active {
        advanceState()
        // Sync any pending entries when app comes to foreground
        Task { @MainActor in
          await SyncService.shared.syncPendingEntries(
            entries: Array(entries),
            profile: profile,
            modelContext: modelContext
          )
        }
      }
    }
  }

  private var loadingView: some View {
    VStack(spacing: Spacing.l) {
      Spacer()
      BrandWordmarkView()
      ProgressView()
        .tint(WQColor.primary)
      Text("warming up your next page")
        .font(Typography.sansCaption)
        .foregroundStyle(WQColor.secondary)
      Spacer()
    }
  }

  @discardableResult
  private func ensureProfile() -> UserProfile {
    // Use direct fetch instead of @Query to avoid timing race where
    // @Query hasn't picked up a just-inserted profile yet.
    let descriptor = FetchDescriptor<UserProfile>()
    if let existing = try? modelContext.fetch(descriptor).first {
      return existing
    }

    let newProfile = UserProfile()
    modelContext.insert(newProfile)
    try? modelContext.save()

    // Authenticate with server (exchanges device UUID for JWT, creates user if needed)
    Task {
      do {
        _ = try await APIClient.shared.authenticate(installDate: newProfile.installDate)
      } catch {
        print("Failed to authenticate with server: \(error)")
      }
    }

    return newProfile
  }

  private func advanceState(profileOverride: UserProfile? = nil) {
    // Don't interrupt overlay sessions (e.g. when app foregrounds)
    if case .freeWrite = currentPhase { return }
    if case .bonusRead = currentPhase { return }

    let effectiveProfile = profileOverride ?? profile

    let resolved = DayEngine.resolveCurrentPhase(
      profile: effectiveProfile,
      entries: Array(entries)
    )
    if resolved != currentPhase {
      currentPhase = resolved
    }
  }
}
