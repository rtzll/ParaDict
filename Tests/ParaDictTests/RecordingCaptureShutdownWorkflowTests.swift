import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingCaptureShutdownWorkflowTests {
  @Test func shortRecordingIsDiscardedInsteadOfReturningCapture() async {
    let recorder = WorkflowStoppingRecorder()
    recorder.currentDuration = 0.5
    let sessionRuntime = RecordingSessionRuntime()
    sessionRuntime.beginActiveCapture(recordingId: "recording-short")
    sessionRuntime.forceStateForTesting(.recording)
    var clearedPresentationCount = 0
    var clearedOverlayCount = 0
    let workflow = RecordingCaptureShutdownWorkflow(
      recorder: recorder,
      sessionRuntime: sessionRuntime,
      clearRecordingPresentation: { clearedPresentationCount += 1 },
      clearOverlayStatus: { clearedOverlayCount += 1 }
    )

    let capture = await workflow.stopCaptureForTranscription()

    #expect(capture == nil)
    #expect(recorder.cancelRecordingCalls == 1)
    #expect(recorder.resetCalls == 1)
    #expect(clearedPresentationCount == 1)
    #expect(clearedOverlayCount == 0)
    #expect(sessionRuntime.recordingState == .idle)
    #expect(sessionRuntime.currentRecordingId == nil)
  }

  @Test func successfulStopReturnsCompletedCaptureAndEntersProcessing() async throws {
    let recorder = WorkflowStoppingRecorder()
    recorder.currentDuration = 2.5
    recorder.actualSampleRate = 16_000
    recorder.actualInputDeviceName = "Desk Mic"
    recorder.stopRecordingResult = try makeAudioFile(named: "capture.wav", size: 8)
    let sessionRuntime = RecordingSessionRuntime()
    sessionRuntime.beginActiveCapture(recordingId: "recording-success")
    sessionRuntime.forceStateForTesting(.recording)
    var clearedPresentationCount = 0
    var clearedOverlayCount = 0
    let workflow = RecordingCaptureShutdownWorkflow(
      recorder: recorder,
      sessionRuntime: sessionRuntime,
      clearRecordingPresentation: { clearedPresentationCount += 1 },
      clearOverlayStatus: { clearedOverlayCount += 1 }
    )

    let capture = await workflow.stopCaptureForTranscription()

    #expect(capture?.recordingId == "recording-success")
    #expect(capture?.duration == 2.5)
    #expect(capture?.sampleRate == 16_000)
    #expect(capture?.inputDeviceName == "Desk Mic")
    #expect(capture?.audioURL == recorder.stopRecordingResult)
    #expect(recorder.stopRecordingCalls == 1)
    #expect(recorder.resetCalls == 0)
    #expect(clearedPresentationCount == 0)
    #expect(clearedOverlayCount == 1)
    #expect(sessionRuntime.recordingState == .processing)
    #expect(sessionRuntime.currentRecordingId == nil)
  }

  @Test func failedStopClearsSessionAndReturnsNil() async {
    let recorder = WorkflowStoppingRecorder()
    recorder.currentDuration = 2.5
    recorder.stopRecordingResult = nil
    let sessionRuntime = RecordingSessionRuntime()
    sessionRuntime.beginActiveCapture(recordingId: "recording-failure")
    sessionRuntime.forceStateForTesting(.recording)
    var clearedPresentationCount = 0
    var clearedOverlayCount = 0
    let workflow = RecordingCaptureShutdownWorkflow(
      recorder: recorder,
      sessionRuntime: sessionRuntime,
      clearRecordingPresentation: { clearedPresentationCount += 1 },
      clearOverlayStatus: { clearedOverlayCount += 1 }
    )

    let capture = await workflow.stopCaptureForTranscription()

    #expect(capture == nil)
    #expect(recorder.stopRecordingCalls == 1)
    #expect(recorder.resetCalls == 1)
    #expect(clearedPresentationCount == 1)
    #expect(clearedOverlayCount == 0)
    #expect(sessionRuntime.recordingState == .idle)
    #expect(sessionRuntime.currentRecordingId == nil)
  }

  @Test func cancellationStopReturnsAudioURLAndClearsSession() async throws {
    let recorder = WorkflowStoppingRecorder()
    recorder.stopRecordingResult = try makeAudioFile(named: "cancel.wav", size: 4)
    let sessionRuntime = RecordingSessionRuntime()
    sessionRuntime.beginActiveCapture(recordingId: "recording-cancel")
    sessionRuntime.forceStateForTesting(.recording)
    var clearedPresentationCount = 0
    let workflow = RecordingCaptureShutdownWorkflow(
      recorder: recorder,
      sessionRuntime: sessionRuntime,
      clearRecordingPresentation: { clearedPresentationCount += 1 },
      clearOverlayStatus: {}
    )

    let audioURL = await workflow.stopCaptureForCancellation()

    #expect(audioURL == recorder.stopRecordingResult)
    #expect(recorder.stopRecordingCalls == 1)
    #expect(recorder.resetCalls == 1)
    #expect(clearedPresentationCount == 1)
    #expect(sessionRuntime.recordingState == .idle)
    #expect(sessionRuntime.currentRecordingId == nil)
  }

  private func makeAudioFile(named name: String, size: Int) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ParaDictShutdownTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try Data(repeating: 0xAB, count: size).write(to: url)
    return url
  }
}

@MainActor
private final class WorkflowStoppingRecorder: RecordingCaptureStopping, @unchecked Sendable {
  var currentDuration: TimeInterval = 0
  var actualSampleRate: Double = 44_100
  var actualInputDeviceName: String = "Test Mic"
  var stopRecordingResult: URL?
  private(set) var stopRecordingCalls = 0
  private(set) var cancelRecordingCalls = 0
  private(set) var resetCalls = 0

  func stopRecording() async -> URL? {
    stopRecordingCalls += 1
    return stopRecordingResult
  }

  func cancelRecording() async {
    cancelRecordingCalls += 1
  }

  func reset() {
    resetCalls += 1
  }
}
