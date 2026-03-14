import Foundation

/// Pre-fetched generation results available to views.
/// Populated once after auth, consumed by ReadView/WriteView.
@MainActor
@Observable
final class PrefetchStore {
  static let shared = PrefetchStore()

  enum ReadingState {
    case idle
    case loading
    case ready(APIClient.EntryResponse)
    case streaming(AsyncThrowingStream<ReadingStreamEvent, Error>)
    case failed(Error)
  }

  enum PromptState {
    case idle
    case loading
    case ready(String)
    case streaming(AsyncThrowingStream<PromptStreamEvent, Error>)
    case failed(Error)
  }

  var reading: ReadingState = .idle
  var prompt: PromptState = .idle

  private var prefetchTask: Task<Void, Never>?

  private init() {}

  /// Fire both generation requests in parallel.
  /// Safe to call multiple times — subsequent calls are no-ops if already loading/ready.
  func prefetch() {
    guard case .idle = reading else { return }
    reading = .loading
    prompt = .loading

    prefetchTask = Task {
      async let readingResult: Void = fetchReading()
      async let promptResult: Void = fetchPrompt()
      _ = await (readingResult, promptResult)
    }
  }

  private func fetchReading() async {
    do {
      let result = try await APIClient.shared.generateReading()
      switch result {
      case .immediate(let event):
        if case .complete(let entry, _) = event {
          reading = .ready(entry)
        }
      case .stream(let stream):
        reading = .streaming(stream)
      }
    } catch {
      reading = .failed(error)
    }
  }

  private func fetchPrompt() async {
    do {
      let result = try await APIClient.shared.generatePrompt()
      switch result {
      case .immediate(let event):
        if case .complete(let promptText, _) = event {
          prompt = .ready(promptText)
        }
      case .stream(let stream):
        prompt = .streaming(stream)
      }
    } catch {
      prompt = .failed(error)
    }
  }

  /// Reset for next session (e.g., when day advances).
  func reset() {
    prefetchTask?.cancel()
    prefetchTask = nil
    reading = .idle
    prompt = .idle
  }
}
