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

struct AudioDeviceSnapshot: Sendable {
  let inputMode: MicInputMode
  let selectedDeviceUID: String?
  let systemDefaultDeviceName: String
  let effectiveDeviceName: String
  let isSelectedDeviceAvailable: Bool
  let availableDevices: [AudioInputDevice]
}

struct RecordingPresentationSnapshot: Sendable {
  let state: RecordingState
  let duration: TimeInterval
  let meterLevel: Double
  let partialTranscript: String
  let overlayStatus: OverlayStatus?
  let overlayHint: OverlayHint?
  let modelReadiness: ModelReadinessMenuPresentation
  let audioDevice: AudioDeviceSnapshot
}

struct OverlaySnapshot: Equatable, Sendable {
  let state: RecordingState
  let duration: TimeInterval
  let meterLevel: Double
  let partialTranscript: String
  let status: OverlayStatus?
  let hint: OverlayHint?
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

/// Durable history for completed and failed recordings.
/// Default conformer: `RecordingHistory`.
@MainActor
protocol RecordingHistoryWriting: AnyObject {
  func saveWithExistingAudio(_ recording: Recording) async throws
  func saveFailedRecording(_ recording: Recording) async throws
  func discardCapture(at audioURL: URL) async
}

/// Writes transcribed text to the system pasteboard and triggers a paste
/// into the frontmost app. Default conformer: `PasteboardService`.
protocol PasteboardWriting: AnyObject {
  func copyAndPaste(_ text: String)
}

struct CompletedRecordingCapture: Sendable {
  let audioURL: URL
  let recordingId: String
  let duration: TimeInterval
  let sampleRate: Double
  let inputDeviceName: String
}

extension ParakeetProvider: TranscriptionProviding {}
extension RecordingHistory: RecordingHistoryWriting {}
extension PasteboardService: PasteboardWriting {}
