import Foundation

enum RecordingTranscriptionOutcome: Equatable, Sendable {
  case succeeded
  case empty
  case failed(String)
}

@MainActor
final class RecordingTranscriptionWorkflow: Sendable {
  private let provider: TranscriptionProviding
  private let recordingPersistence: RecordingPersisting
  private let analyticsRecording: AnalyticsRecording
  private let pasteboardWriter: PasteboardWriting

  init(
    provider: TranscriptionProviding,
    recordingPersistence: RecordingPersisting,
    analyticsRecording: AnalyticsRecording,
    pasteboardWriter: PasteboardWriting
  ) {
    self.provider = provider
    self.recordingPersistence = recordingPersistence
    self.analyticsRecording = analyticsRecording
    self.pasteboardWriter = pasteboardWriter
  }

  func process(_ capture: CompletedRecordingCapture) async -> RecordingTranscriptionOutcome {
    do {
      let result = try await provider.transcribe(audioURL: capture.audioURL)

      guard !result.text.isEmpty else {
        return .empty
      }

      pasteboardWriter.copyAndPaste(result.text)

      let recording = Recording.completed(
        id: capture.recordingId,
        audioURL: capture.audioURL,
        transcriptionResult: result,
        duration: capture.duration,
        sampleRate: capture.sampleRate,
        inputDeviceName: capture.inputDeviceName
      )

      try await recordingPersistence.saveWithExistingAudio(recording)
      await analyticsRecording.record(
        duration: capture.duration,
        wordCount: result.text.split(separator: " ").count
      )
      return .succeeded
    } catch {
      try? await recordingPersistence.saveFailedRecording(
        Recording.failed(
          id: capture.recordingId,
          duration: capture.duration,
          sampleRate: capture.sampleRate,
          inputDeviceName: capture.inputDeviceName
        ))
      return .failed(error.localizedDescription)
    }
  }
}
