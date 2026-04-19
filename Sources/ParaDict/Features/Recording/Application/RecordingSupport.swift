@preconcurrency import FluidAudio
import Foundation

enum OverlayStatusKind: Sendable {
  case info
  case warning
  case error
}

struct OverlayStatus: Sendable, Equatable {
  let kind: OverlayStatusKind
  let title: String
  let message: String?
}

struct OverlayHint: Sendable, Equatable {
  let message: String
}

/// Loads the ASR model and turns a recorded audio file into text.
/// Default conformer: `ParakeetProvider`.
@MainActor
protocol TranscriptionProviding: AnyObject {
  var isInitialized: Bool { get }
  func initialize() async throws
  func models() async throws -> AsrModels
  func transcribe(audioURL: URL) async throws -> TranscriptionResult
}

/// Durable storage for completed and failed recordings.
/// Default conformer: `RecordingStore`.
@MainActor
protocol RecordingPersisting: AnyObject {
  func saveWithExistingAudio(_ recording: Recording) async throws
  func saveFailedRecording(_ recording: Recording) async throws
}

/// Aggregates per-recording metrics (total duration, word counts) for the
/// menu bar stats row. Default conformer: `AnalyticsStore`.
@MainActor
protocol AnalyticsRecording: AnyObject {
  func record(duration: TimeInterval, wordCount: Int) async
}

/// Writes transcribed text to the system pasteboard and triggers a paste
/// into the frontmost app. Default conformer: `PasteboardService`.
protocol PasteboardWriting: AnyObject {
  func copyAndPaste(_ text: String)
}

struct CompletedRecordingCapture {
  let audioURL: URL
  let recordingId: String
  let duration: TimeInterval
  let sampleRate: Double
  let inputDeviceName: String
}

extension ParakeetProvider: TranscriptionProviding {}
extension RecordingStore: RecordingPersisting {}
extension AnalyticsStore: AnalyticsRecording {}
extension PasteboardService: PasteboardWriting {}
