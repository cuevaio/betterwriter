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

  /// Enqueue new text for word-fade reveal.
  func enqueue(_ text: String, into binding: Binding<String>) {
    let chunks = Self.wordChunks(from: text)
    pendingChunks.append(contentsOf: chunks)
    guard revealTask == nil || revealTask!.isCancelled else { return }
    revealTask = Task {
      while !pendingChunks.isEmpty && !Task.isCancelled {
        let chunk = pendingChunks.removeFirst()
        withAnimation(.easeIn(duration: 0.12)) {
          binding.wrappedValue += chunk
        }
        let delay: UInt64 = chunk.count <= 2 ? 20_000_000 : 40_000_000
        try? await Task.sleep(nanoseconds: delay)
      }
      revealTask = nil
    }
  }

  /// Cancel any in-flight reveal and clear pending chunks.
  func cancel() {
    revealTask?.cancel()
    revealTask = nil
    pendingChunks.removeAll()
  }

  /// Wait for the current reveal task to finish.
  func waitForCompletion() async {
    if let task = revealTask { await task.value }
  }

  /// Split text on whitespace boundaries, keeping trailing space
  /// attached to each word so re-joining is lossless.
  static func wordChunks(from text: String) -> [String] {
    guard !text.isEmpty else { return [] }
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
