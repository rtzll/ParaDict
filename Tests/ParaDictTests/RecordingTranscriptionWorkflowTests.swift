@preconcurrency import FluidAudio
import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingTranscriptionWorkflowTests {
  @Test func successfulTranscriptionCopiesPersistsAndTracksAnalytics() async throws {
    let provider = TestTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "hello world",
      segments: [],
      language: "en",
      duration: 0.4,
      model: "test"
    )
    let recordings = TestRecordingPersistence()
    let analytics = TestAnalyticsRecorder()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingPersistence: recordings,
      analyticsRecording: analytics,
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
    #expect(analytics.calls.count == 1)
    #expect(analytics.calls[0].wordCount == 2)
  }

  @Test func emptyTranscriptionReturnsEmptyWithoutSideEffects() async throws {
    let provider = TestTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "",
      segments: [],
      language: "en",
      duration: 0.1,
      model: "test"
    )
    let recordings = TestRecordingPersistence()
    let analytics = TestAnalyticsRecorder()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingPersistence: recordings,
      analyticsRecording: analytics,
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
    #expect(analytics.calls.isEmpty)
  }

  @Test func failedTranscriptionPersistsFailedRecording() async throws {
    let provider = TestTranscriptionProvider()
    provider.error = NSError(
      domain: "RecordingTranscriptionWorkflowTests",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "transcriber exploded"]
    )
    let recordings = TestRecordingPersistence()
    let analytics = TestAnalyticsRecorder()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingPersistence: recordings,
      analyticsRecording: analytics,
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
    #expect(analytics.calls.isEmpty)
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
    let analytics = TestAnalyticsRecorder()
    let pasteboard = TestPasteboardWriter()
    let workflow = RecordingTranscriptionWorkflow(
      provider: provider,
      recordingPersistence: recordings,
      analyticsRecording: analytics,
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
    #expect(analytics.calls.isEmpty)
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
