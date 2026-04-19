@preconcurrency import FluidAudio
import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingTranscriptionWorkflowTests {
  @Test func successfulTranscriptionCopiesPersistsAndTracksAnalytics() async throws {
    let provider = WorkflowTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "hello world",
      segments: [],
      language: "en",
      duration: 0.4,
      model: "test"
    )
    let recordings = WorkflowRecordingPersistence()
    let analytics = WorkflowAnalyticsRecorder()
    let pasteboard = WorkflowPasteboardWriter()
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
    let provider = WorkflowTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "",
      segments: [],
      language: "en",
      duration: 0.1,
      model: "test"
    )
    let recordings = WorkflowRecordingPersistence()
    let analytics = WorkflowAnalyticsRecorder()
    let pasteboard = WorkflowPasteboardWriter()
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
    let provider = WorkflowTranscriptionProvider()
    provider.error = NSError(
      domain: "RecordingTranscriptionWorkflowTests",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "transcriber exploded"]
    )
    let recordings = WorkflowRecordingPersistence()
    let analytics = WorkflowAnalyticsRecorder()
    let pasteboard = WorkflowPasteboardWriter()
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
    let provider = WorkflowTranscriptionProvider()
    provider.result = TranscriptionResult(
      text: "hello world",
      segments: [],
      language: "en",
      duration: 0.4,
      model: "test"
    )
    let recordings = WorkflowRecordingPersistence()
    recordings.completedSaveError = NSError(
      domain: "RecordingTranscriptionWorkflowTests",
      code: 9,
      userInfo: [NSLocalizedDescriptionKey: "save failed"]
    )
    let analytics = WorkflowAnalyticsRecorder()
    let pasteboard = WorkflowPasteboardWriter()
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

@MainActor
private final class WorkflowTranscriptionProvider: TranscriptionProviding, @unchecked Sendable {
  var isInitialized = true
  var result = TranscriptionResult(
    text: "",
    segments: [],
    language: "en",
    duration: 0,
    model: "fake"
  )
  var error: Error?

  func initialize() async throws {}

  func models() async throws -> AsrModels {
    fatalError("Unused in RecordingTranscriptionWorkflowTests")
  }

  func transcribe(audioURL: URL) async throws -> TranscriptionResult {
    if let error {
      throw error
    }
    return result
  }
}

@MainActor
private final class WorkflowRecordingPersistence: RecordingPersisting, @unchecked Sendable {
  var completedSaveError: Error?
  private(set) var completedRecordings: [Recording] = []
  private(set) var failedRecordings: [Recording] = []

  func saveWithExistingAudio(_ recording: Recording) async throws {
    if let completedSaveError {
      throw completedSaveError
    }
    completedRecordings.append(recording)
  }

  func saveFailedRecording(_ recording: Recording) async throws {
    failedRecordings.append(recording)
  }
}

@MainActor
private final class WorkflowAnalyticsRecorder: AnalyticsRecording, @unchecked Sendable {
  struct Call {
    let duration: TimeInterval
    let wordCount: Int
  }

  private(set) var calls: [Call] = []

  func record(duration: TimeInterval, wordCount: Int) async {
    calls.append(Call(duration: duration, wordCount: wordCount))
  }
}

private final class WorkflowPasteboardWriter: PasteboardWriting, @unchecked Sendable {
  private(set) var copiedTexts: [String] = []

  func copyAndPaste(_ text: String) {
    copiedTexts.append(text)
  }
}
