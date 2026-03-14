import SwiftUI

/// Shared word-fade animation engine for streaming text content.
/// Splits incoming text into word-boundary chunks and reveals them
/// one at a time with a fade-in animation.
@MainActor
final class TypewriterAnimator {
  /// The text revealed so far (animated).
  private(set) var displayedText = ""
  /// Queued chunks waiting to be revealed.
  private var pendingChunks: [String] = []
  /// The running reveal task.
  private var revealTask: Task<Void, Never>?
  /// Whether the current reveal is running in fast mode.
  private var isFastMode = false

  /// Enqueue new text for word-fade reveal.
  /// - Parameters:
  ///   - text: The text to reveal.
  ///   - binding: The binding to update with revealed text.
  ///   - fast: When true, batches 5 words at a time with 10ms delays
  ///     for pre-fetched/cached content (~1.6s for 800 words).
  ///     When false, reveals one word at a time with 20-40ms delays
  ///     for real-time SSE deltas.
  func enqueue(
    _ text: String, into binding: Binding<String>, fast: Bool = false
  ) {
    let chunks =
      fast
      ? Self.wordChunks(from: text, batchSize: 5)
      : Self.wordChunks(from: text)
    pendingChunks.append(contentsOf: chunks)
    if fast { isFastMode = true }
    guard revealTask == nil || revealTask!.isCancelled else { return }
    let useFast = isFastMode
    revealTask = Task {
      while !pendingChunks.isEmpty && !Task.isCancelled {
        let chunk = pendingChunks.removeFirst()
        withAnimation(.easeIn(duration: 0.12)) {
          binding.wrappedValue += chunk
        }
        let delay: UInt64 =
          useFast
          ? 10_000_000
          : (chunk.count <= 2 ? 20_000_000 : 40_000_000)
        try? await Task.sleep(nanoseconds: delay)
      }
      revealTask = nil
      isFastMode = false
    }
  }

  /// Cancel any in-flight reveal and clear pending chunks.
  func cancel() {
    revealTask?.cancel()
    revealTask = nil
    pendingChunks.removeAll()
    isFastMode = false
  }

  /// Wait for the current reveal task to finish.
  func waitForCompletion() async {
    if let task = revealTask { await task.value }
  }

  /// Split text on whitespace boundaries, keeping trailing space
  /// attached to each word so re-joining is lossless.
  /// - Parameter batchSize: Number of words to group per chunk.
  ///   Default is 1 (one word per chunk). Use higher values for
  ///   faster reveal of cached content.
  static func wordChunks(
    from text: String, batchSize: Int = 1
  ) -> [String] {
    guard !text.isEmpty else { return [] }
    let words = basicWordChunks(from: text)
    if batchSize <= 1 { return words }

    // Batch words together for faster reveal
    var batched: [String] = []
    var current = ""
    for (i, word) in words.enumerated() {
      current += word
      if (i + 1) % batchSize == 0 || i == words.count - 1 {
        batched.append(current)
        current = ""
      }
    }
    return batched
  }

  /// Core word splitting — one word per chunk.
  private static func basicWordChunks(from text: String) -> [String] {
    var chunks: [String] = []
    var current = ""
    for ch in text {
      current.append(ch)
      if ch.isWhitespace
        && !current.trimmingCharacters(in: .whitespaces).isEmpty
      {
        chunks.append(current)
        current = ""
      }
    }
    if !current.isEmpty { chunks.append(current) }
    return chunks
  }
}
