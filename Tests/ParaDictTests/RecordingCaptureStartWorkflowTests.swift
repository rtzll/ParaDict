import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingCaptureStartWorkflowTests {
  @Test func modelNotReadyShowsErrorAndDoesNotStart() async {
    let recorder = WorkflowStartingRecorder()
    let toast = WorkflowToastPresenter()
    let sessionRuntime = RecordingSessionRuntime()
    let workflow = RecordingCaptureStartWorkflow(
      recorder: recorder,
      mediaPlayback: MediaPlaybackController(),
      sessionRuntime: sessionRuntime,
      capturePreparationWorkflow: WorkflowCapturePreparing(),
      toast: toast,
      callbacks: RecordingCaptureStartWorkflow.Callbacks(
        isModelLoaded: { false },
        clearOverlayStatus: {},
        startDurationChecks: {},
        onPreviewUpdate: { _ in },
        onPreviewStartupFailure: {},
        onRecordingStarted: {}
      )
    )

    await workflow.startRecording()

    #expect(recorder.startCalls == 0)
    #expect(sessionRuntime.recordingState == .idle)
    #expect(toast.errors.count == 1)
    #expect(toast.errors[0].title == "Model Not Ready")
  }

  @Test func noInputDeviceShowsErrorAndResetsState() async {
    let recorder = WorkflowStartingRecorder()
    let toast = WorkflowToastPresenter()
    let sessionRuntime = RecordingSessionRuntime()
    let preparation = WorkflowCapturePreparing()
    preparation.prepareOutcome = .noInputDevice
    let workflow = RecordingCaptureStartWorkflow(
      recorder: recorder,
      mediaPlayback: MediaPlaybackController(),
      sessionRuntime: sessionRuntime,
      capturePreparationWorkflow: preparation,
      toast: toast,
      callbacks: RecordingCaptureStartWorkflow.Callbacks(
        isModelLoaded: { true },
        clearOverlayStatus: {},
        startDurationChecks: {},
        onPreviewUpdate: { _ in },
        onPreviewStartupFailure: {},
        onRecordingStarted: {}
      )
    )

    await workflow.startRecording()

    #expect(recorder.startCalls == 0)
    #expect(recorder.resetCalls == 1)
    #expect(sessionRuntime.recordingState == .idle)
    #expect(sessionRuntime.currentRecordingId == nil)
    #expect(toast.errors.count == 1)
    #expect(toast.errors[0].title == "Recording Failed")
  }

  @Test func startFailureResetsRecorderAndSession() async {
    let recorder = WorkflowStartingRecorder()
    recorder.startError = NSError(
      domain: "RecordingCaptureStartWorkflowTests",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "cannot start recorder"]
    )
    let toast = WorkflowToastPresenter()
    let sessionRuntime = RecordingSessionRuntime()
    let preparation = WorkflowCapturePreparing()
    preparation.prepareOutcome = .ready(
      RecordingSessionPreparation(
        session: PendingRecordingSession(
          recordingId: "recording-start-failure",
          resolvedDevice: ResolvedRecordingDevice(
            deviceID: 42,
            resolvedDeviceName: "Mic",
            didFallbackToSystemDefault: false,
            requestedMode: .systemDefault
          ),
          audioURL: URL(fileURLWithPath: "/tmp/recording-start-failure.wav"),
          streamingSession: ParakeetStreamingSession()
        ),
        didFallbackToSystemDefault: false
      ))
    var partialTranscript = "existing"
    let workflow = RecordingCaptureStartWorkflow(
      recorder: recorder,
      mediaPlayback: MediaPlaybackController(),
      sessionRuntime: sessionRuntime,
      capturePreparationWorkflow: preparation,
      toast: toast,
      callbacks: RecordingCaptureStartWorkflow.Callbacks(
        isModelLoaded: { true },
        clearOverlayStatus: {},
        startDurationChecks: {},
        onPreviewUpdate: { update in
          if case .reset = update {
            partialTranscript = ""
          }
        },
        onPreviewStartupFailure: {},
        onRecordingStarted: {}
      )
    )

    await workflow.startRecording()

    #expect(recorder.startCalls == 1)
    #expect(recorder.resetCalls == 1)
    #expect(recorder.onAudioChunk == nil)
    #expect(partialTranscript.isEmpty)
    #expect(sessionRuntime.recordingState == .idle)
    #expect(sessionRuntime.currentRecordingId == nil)
    #expect(toast.errors.count == 1)
    #expect(toast.errors[0].message == "cannot start recorder")
  }
}

@MainActor
private final class WorkflowStartingRecorder: RecordingCaptureStarting, @unchecked Sendable {
  var actualSampleRate: Double = 16_000
  var onAudioChunk: ((Data) -> Void)?
  var startError: Error?
  private(set) var startCalls = 0
  private(set) var resetCalls = 0

  func startRecording(to url: URL, resolvedDevice: ResolvedRecordingDevice) async throws {
    startCalls += 1
    if let startError {
      throw startError
    }
  }

  func reset() {
    resetCalls += 1
  }
}

@MainActor
private final class WorkflowCapturePreparing: RecordingCapturePreparing, @unchecked Sendable {
  var prepareOutcome: RecordingSessionPreparationOutcome = .noInputDevice
  var previewResult: Result<Void, Error> = .success(())

  func preparePendingSession(recordingId: String) -> RecordingSessionPreparationOutcome {
    prepareOutcome
  }

  func startStreamingPreview(
    for session: PendingRecordingSession,
    inputSampleRate: Double,
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) async -> Result<Void, Error> {
    previewResult
  }
}

@MainActor
private final class WorkflowToastPresenter: ToastPresenting, @unchecked Sendable {
  private(set) var messages: [ToastMessage] = []
  private(set) var errors: [(title: String, message: String?)] = []

  func show(_ toast: ToastMessage, anchor: ToastWindowController.Anchor) {
    messages.append(toast)
  }

  func showError(title: String, message: String?) {
    errors.append((title, message))
  }
}
