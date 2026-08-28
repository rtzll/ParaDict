import Foundation

struct WordTiming: Codable, Equatable, Hashable, Sendable {
  let word: String
  let start: TimeInterval
  let end: TimeInterval
  let probability: Float
}

struct TranscriptionSegment: Codable, Equatable, Hashable, Identifiable, Sendable {
  var id: String { "\(start)-\(end)" }

  let start: TimeInterval
  let end: TimeInterval
  let text: String
  let words: [WordTiming]?
}

struct TranscriptionResult: Sendable {
  let text: String
  /// Original ASR text when `text` has been post-processed.
  let rawText: String?
  let segments: [TranscriptionSegment]
  let language: String
  let duration: TimeInterval
  let model: String

  init(
    text: String,
    rawText: String? = nil,
    segments: [TranscriptionSegment],
    language: String,
    duration: TimeInterval,
    model: String
  ) {
    self.text = text
    self.rawText = rawText
    self.segments = segments
    self.language = language
    self.duration = duration
    self.model = model
  }
}

struct SegmentsResult: Codable, Equatable, Sendable {
  let segments: [TranscriptionSegment]
  let totalDuration: TimeInterval
  let wordTimestampsEnabled: Bool
}
