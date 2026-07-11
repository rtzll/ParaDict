import Foundation

enum RecordingTranscriptionOutcome: Equatable, Sendable {
  case succeeded
  case empty
  case failed(String)
}

@MainActor
final class RecordingTranscriptionWorkflow: Sendable {
  private let provider: TranscriptionProviding
  private let recordingHistory: RecordingHistoryWriting
  private let pasteboardWriter: PasteboardWriting

  init(
    provider: TranscriptionProviding,
    recordingHistory: RecordingHistoryWriting,
    pasteboardWriter: PasteboardWriting
  ) {
    self.provider = provider
    self.recordingHistory = recordingHistory
    self.pasteboardWriter = pasteboardWriter
  }

  func process(_ capture: CompletedRecordingCapture) async -> RecordingTranscriptionOutcome {
    do {
      let result = try await provider.transcribe(audioURL: capture.audioURL)

      guard !result.text.isEmpty else {
        await recordingHistory.discardCapture(at: capture.audioURL)
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

      try await recordingHistory.saveWithExistingAudio(recording)
      return .succeeded
    } catch {
      try? await recordingHistory.saveFailedRecording(
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
