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
  private let cleanupProvider: (any TranscriptCleanupProviding)?

  init(
    provider: TranscriptionProviding,
    recordingHistory: RecordingHistoryWriting,
    pasteboardWriter: PasteboardWriting,
    cleanupProvider: (any TranscriptCleanupProviding)? = nil
  ) {
    self.provider = provider
    self.recordingHistory = recordingHistory
    self.pasteboardWriter = pasteboardWriter
    self.cleanupProvider = cleanupProvider
  }

  func process(_ capture: CompletedRecordingCapture) async -> RecordingTranscriptionOutcome {
    do {
      let result = try await provider.transcribe(audioURL: capture.audioURL)

      guard !result.text.isEmpty else {
        await recordingHistory.discardCapture(at: capture.audioURL)
        return .empty
      }

      let finalResult = await applyingCleanup(to: result)

      guard !finalResult.text.isEmpty else {
        await recordingHistory.discardCapture(at: capture.audioURL)
        return .empty
      }

      pasteboardWriter.copyAndPaste(finalResult.text)

      let recording = Recording.completed(
        id: capture.recordingId,
        audioURL: capture.audioURL,
        transcriptionResult: finalResult,
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

  /// Runs the transcript through the cleanup model when one is available;
  /// keeps the raw text if cleanup is disabled, not ready, or fails.
  private func applyingCleanup(to result: TranscriptionResult) async -> TranscriptionResult {
    guard let cleanupProvider else { return result }

    guard case .cleaned(let cleanedText) = await cleanupProvider.cleanup(result.text) else {
      return result
    }

    return TranscriptionResult(
      text: cleanedText,
      rawText: result.text,
      segments: result.segments,
      language: result.language,
      duration: result.duration,
      model: result.model
    )
  }
}
