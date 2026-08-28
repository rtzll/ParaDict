@preconcurrency import FluidAudio
import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingTranscriptionWorkflowTests {
  @Test func successfulTranscriptionCopiesAndPersistsRecording() async throws {
    let provider = TestTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "hello world",
      segments: [],
      language: "en",
      duration: 0.4,
      model: "test"
    )
    let recordings = TestRecordingPersistence()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingHistory: recordings,
      pasteboardWriter: pasteboard
    )

    let outcome = await workflow.process(
      try makeCapture(
        recordingId: "recording-success",
        fileName: "success.wav",
        fileSize: 8
      ))

    #expect(outcome == .succeeded)
    #expect(pasteboard.copiedTexts == ["hello world"])
    #expect(recordings.completedRecordings.count == 1)
    #expect(recordings.failedRecordings.isEmpty)
  }

  @Test func emptyTranscriptionDiscardsCapturedAudio() async throws {
    let provider = TestTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "",
      segments: [],
      language: "en",
      duration: 0.1,
      model: "test"
    )
    let recordings = TestRecordingPersistence()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingHistory: recordings,
      pasteboardWriter: pasteboard
    )

    let outcome = await workflow.process(
      try makeCapture(
        recordingId: "recording-empty",
        fileName: "empty.wav",
        fileSize: 4
      ))

    #expect(outcome == .empty)
    #expect(pasteboard.copiedTexts.isEmpty)
    #expect(recordings.completedRecordings.isEmpty)
    #expect(recordings.failedRecordings.isEmpty)
    #expect(recordings.discardedAudioURLs.count == 1)
  }

  @Test func failedTranscriptionPersistsFailedRecording() async throws {
    let provider = TestTranscriptionProvider()
    provider.error = NSError(
      domain: "RecordingTranscriptionWorkflowTests",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "transcriber exploded"]
    )
    let recordings = TestRecordingPersistence()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingHistory: recordings,
      pasteboardWriter: pasteboard
    )

    let outcome = await workflow.process(
      try makeCapture(
        recordingId: "recording-failure",
        fileName: "failure.wav",
        fileSize: 6
      ))

    #expect(outcome == .failed("transcriber exploded"))
    #expect(pasteboard.copiedTexts.isEmpty)
    #expect(recordings.completedRecordings.isEmpty)
    #expect(recordings.failedRecordings.count == 1)
    #expect(recordings.failedRecordings[0].id == "recording-failure")
  }

  @Test func persistenceFailureDowngradesToFailedRecording() async throws {
    let provider = TestTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "hello world",
      segments: [],
      language: "en",
      duration: 0.4,
      model: "test"
    )
    let recordings = TestRecordingPersistence()
    recordings.completedSaveError = NSError(
      domain: "RecordingTranscriptionWorkflowTests",
      code: 9,
      userInfo: [NSLocalizedDescriptionKey: "save failed"]
    )
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingHistory: recordings,
      pasteboardWriter: pasteboard
    )

    let outcome = await workflow.process(
      try makeCapture(
        recordingId: "recording-save-error",
        fileName: "save-error.wav",
        fileSize: 8
      ))

    #expect(outcome == .failed("save failed"))
    #expect(pasteboard.copiedTexts == ["hello world"])
    #expect(recordings.completedRecordings.isEmpty)
    #expect(recordings.failedRecordings.count == 1)
    #expect(recordings.failedRecordings[0].id == "recording-save-error")
  }

  @Test func cleanupReplacesTextForPasteAndHistory() async throws {
    let provider = TestTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "hello world",
      segments: [],
      language: "en",
      duration: 0.4,
      model: "test"
    )
    let cleanup = TestCleanupProvider()
    cleanup.result = .cleaned("Hello, world!")
    let recordings = TestRecordingPersistence()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingHistory: recordings,
      pasteboardWriter: pasteboard,
      cleanupProvider: cleanup
    )

    let outcome = await workflow.process(
      try makeCapture(
        recordingId: "recording-cleanup",
        fileName: "cleanup.wav",
        fileSize: 8
      ))

    #expect(outcome == .succeeded)
    #expect(cleanup.receivedTexts == ["hello world"])
    #expect(pasteboard.copiedTexts == ["Hello, world!"])
    #expect(recordings.completedRecordings.count == 1)
    #expect(recordings.completedRecordings[0].transcription?.text == "Hello, world!")
    #expect(recordings.completedRecordings[0].transcription?.rawText == "hello world")
  }

  @Test func cleanupFallbackKeepsRawText() async throws {
    let provider = TestTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "hello world",
      segments: [],
      language: "en",
      duration: 0.4,
      model: "test"
    )
    let cleanup = TestCleanupProvider()
    cleanup.result = .unavailable
    let recordings = TestRecordingPersistence()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingHistory: recordings,
      pasteboardWriter: pasteboard,
      cleanupProvider: cleanup
    )

    let outcome = await workflow.process(
      try makeCapture(
        recordingId: "recording-cleanup-fallback",
        fileName: "cleanup-fallback.wav",
        fileSize: 8
      ))

    #expect(outcome == .succeeded)
    #expect(pasteboard.copiedTexts == ["hello world"])
    #expect(recordings.completedRecordings[0].transcription?.text == "hello world")
    #expect(recordings.completedRecordings[0].transcription?.rawText == nil)
  }

  @Test func emptyCleanupResultDiscardsFillerWithoutPasting() async throws {
    let provider = TestTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "um",
      segments: [],
      language: "en",
      duration: 0.2,
      model: "test"
    )
    let cleanup = TestCleanupProvider()
    cleanup.result = .cleaned("")
    let recordings = TestRecordingPersistence()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingHistory: recordings,
      pasteboardWriter: pasteboard,
      cleanupProvider: cleanup
    )

    let outcome = await workflow.process(
      try makeCapture(
        recordingId: "recording-cleanup-empty",
        fileName: "cleanup-empty.wav",
        fileSize: 8
      ))

    #expect(outcome == .empty)
    #expect(cleanup.receivedTexts == ["um"])
    #expect(pasteboard.copiedTexts.isEmpty)
    #expect(recordings.completedRecordings.isEmpty)
    #expect(recordings.discardedAudioURLs.count == 1)
  }

  @Test func cleanupSkippedWhenProviderReturnsNothingUsable() async throws {
    let provider = TestTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "hello world",
      segments: [],
      language: "en",
      duration: 0.4,
      model: "test"
    )
    let recordings = TestRecordingPersistence()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingHistory: recordings,
      pasteboardWriter: pasteboard,
      cleanupProvider: nil
    )

    let outcome = await workflow.process(
      try makeCapture(
        recordingId: "recording-no-cleanup",
        fileName: "no-cleanup.wav",
        fileSize: 8
      ))

    #expect(outcome == .succeeded)
    #expect(pasteboard.copiedTexts == ["hello world"])
  }

  private func makeCapture(recordingId: String, fileName: String, fileSize: Int) throws
    -> CompletedRecordingCapture
  {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ParaDictWorkflowTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(fileName)
    try Data(repeating: 0xAB, count: fileSize).write(to: url)
    return CompletedRecordingCapture(
      audioURL: url,
      recordingId: recordingId,
      duration: 2.5,
      sampleRate: 16_000,
      inputDeviceName: "Test Mic"
    )
  }
}
