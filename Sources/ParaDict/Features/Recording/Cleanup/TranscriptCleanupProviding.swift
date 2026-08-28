import Foundation

enum TranscriptCleanupResult: Equatable, Sendable {
  /// Cleanup completed successfully. An empty string is a valid result for
  /// filler-only or noise-only transcripts.
  case cleaned(String)

  /// Cleanup was disabled, not ready, or failed. Callers should retain the
  /// original transcript.
  case unavailable
}

/// Post-processes a raw transcription before it is pasted or persisted.
protocol TranscriptCleanupProviding: Sendable {
  func cleanup(_ text: String) async -> TranscriptCleanupResult
}
