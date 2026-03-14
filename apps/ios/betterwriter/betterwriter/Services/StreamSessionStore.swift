import Foundation

/// Lightweight concurrency guard for stream loading operations.
/// Prevents duplicate concurrent loads for the same entity.
@MainActor
final class StreamSessionStore {
  static let shared = StreamSessionStore()

  /// In-memory set preventing concurrent loads for the same entity.
  private var activeLoads: Set<String> = []

  private init() {}

  // MARK: - Concurrency guard

  /// Returns `true` if the load was claimed; `false` if one is already in progress.
  func beginLoad(key: String) -> Bool {
    guard !activeLoads.contains(key) else { return false }
    activeLoads.insert(key)
    return true
  }

  func endLoad(key: String) {
    activeLoads.remove(key)
  }
}
