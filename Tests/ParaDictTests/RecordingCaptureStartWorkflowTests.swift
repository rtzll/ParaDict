import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingCaptureStartWorkflowTests {
  @Test func pausesMediaBeforeStartingCapture() async {
    let events = TestEventLog()
    let recorder = WorkflowStartingRecorder()
    recorder.eventLog = events
    let mediaClient = FakeMediaRemote()
    mediaClient.audioActive = true
    mediaClient.eventLog = events
    let preparation = WorkflowCapturePreparing()
    preparation.prepareOutcome = .ready(
      RecordingSessionPreparation(
        session: PendingRecordingSession(
          recordingId: "recording-order",
          resolvedDevice: ResolvedRecordingDevice(
            deviceID: 42,
            resolvedDeviceName: "Mic",
            didFallbackToSystemDefault: false,
            requestedMode: .systemDefault
          ),
          audioURL: URL(fileURLWithPath: "/tmp/recording-order.wav"),
          streamingSession: LivePreviewSession()
        ),
        didFallbackToSystemDefault: false
      ))
    let workflow = RecordingCaptureStartWorkflow(
      recorder: recorder,
      mediaPlayback: MediaPlaybackController(client: mediaClient),
      sessionRuntime: RecordingSessionRuntime(),
      modelReadiness: WorkflowModelReadiness(),
      capturePreparationWorkflow: preparation,
      feedbackPresenter: WorkflowToastPresenter()
    )

    let outcome = await workflow.startRecording { _ in }

    #expect(outcome == .started)
    #expect(events.events.prefix(2) == ["pause-media", "capture-start"])
  }

  @Test func modelNotReadyShowsErrorAndDoesNotStart() async {
    let recorder = WorkflowStartingRecorder()
    let toast = WorkflowToastPresenter()
    let sessionRuntime = RecordingSessionRuntime()
    let workflow = RecordingCaptureStartWorkflow(
      recorder: recorder,
      mediaPlayback: MediaPlaybackController(),
      sessionRuntime: sessionRuntime,
      modelReadiness: WorkflowModelReadiness(
        startFailure: ModelReadinessFailure(
          title: "Model Loading",
          message: "Please wait for Parakeet to finish loading."
        )),
      capturePreparationWorkflow: WorkflowCapturePreparing(),
      feedbackPresenter: toast
    )

    let outcome = await workflow.startRecording { _ in }

    #expect(outcome == .notStarted)

    #expect(recorder.startCalls == 0)
    #expect(sessionRuntime.recordingState == .idle)
    #expect(toast.errors.count == 1)
    #expect(toast.errors[0].title == "Model Loading")
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
      modelReadiness: WorkflowModelReadiness(),
      capturePreparationWorkflow: preparation,
      feedbackPresenter: toast
    )

    let outcome = await workflow.startRecording { _ in }

    #expect(outcome == .notStarted)

    #expect(recorder.startCalls == 0)
    #expect(recorder.resetCalls == 1)
    #expect(sessionRuntime.recordingState == .idle)
    #expect(sessionRuntime.currentRecordingId == nil)
    #expect(toast.errors.count == 1)
    #expect(toast.errors[0].title == "Recording Failed")
  }

  @Test func previewStartupFailureKeepsRecordingAndReportsFeedback() async {
    let recorder = WorkflowStartingRecorder()
    let toast = WorkflowToastPresenter()
    let sessionRuntime = RecordingSessionRuntime()
    let preparation = WorkflowCapturePreparing()
    preparation.prepareOutcome = .ready(
      RecordingSessionPreparation(
        session: PendingRecordingSession(
          recordingId: "recording-preview-failure",
          resolvedDevice: ResolvedRecordingDevice(
            deviceID: 42,
            resolvedDeviceName: "Mic",
            didFallbackToSystemDefault: false,
            requestedMode: .systemDefault
          ),
          audioURL: URL(fileURLWithPath: "/tmp/recording-preview-failure.wav"),
          streamingSession: LivePreviewSession()
        ),
        didFallbackToSystemDefault: false
      ))
    preparation.previewResult = .failure(
      NSError(
        domain: "RecordingCaptureStartWorkflowTests",
        code: 8,
        userInfo: [NSLocalizedDescriptionKey: "preview failed"]
      ))
    var previewUpdates: [StreamingPreviewUpdate] = []
    let workflow = RecordingCaptureStartWorkflow(
      recorder: recorder,
      mediaPlayback: MediaPlaybackController(),
      sessionRuntime: sessionRuntime,
      modelReadiness: WorkflowModelReadiness(),
      capturePreparationWorkflow: preparation,
      feedbackPresenter: toast
    )

    let outcome = await workflow.startRecording { update in
      previewUpdates.append(update)
    }

    #expect(outcome == .started)
    #expect(recorder.startCalls == 1)
    #expect(recorder.onAudioChunk == nil)
    #expect(sessionRuntime.recordingState == .recording)
    #expect(previewUpdates == [.reset, .reset])
    #expect(toast.feedback.contains(RecordingFeedback(.livePreviewUnavailable)))
  }

  @Test func startFailureResetsRecorderAndSession() async {
    let events = TestEventLog()
    let recorder = WorkflowStartingRecorder()
    recorder.eventLog = events
    recorder.startError = NSError(
      domain: "RecordingCaptureStartWorkflowTests",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "cannot start recorder"]
    )
    let mediaClient = FakeMediaRemote()
    mediaClient.audioActive = true
    mediaClient.eventLog = events
    recorder.mediaClientToDeactivate = mediaClient
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
          streamingSession: LivePreviewSession()
        ),
        didFallbackToSystemDefault: false
      ))
    var partialTranscript = "existing"
    let workflow = RecordingCaptureStartWorkflow(
      recorder: recorder,
      mediaPlayback: MediaPlaybackController(client: mediaClient),
      sessionRuntime: sessionRuntime,
      modelReadiness: WorkflowModelReadiness(),
      capturePreparationWorkflow: preparation,
      feedbackPresenter: toast
    )

    let outcome = await workflow.startRecording { update in
      if case .reset = update {
        partialTranscript = ""
      }
    }

    #expect(outcome == .notStarted)

    #expect(recorder.startCalls == 1)
    #expect(recorder.resetCalls == 1)
    #expect(recorder.onAudioChunk == nil)
    #expect(partialTranscript.isEmpty)
    #expect(sessionRuntime.recordingState == .idle)
    #expect(sessionRuntime.currentRecordingId == nil)
    #expect(toast.errors.count == 1)
    #expect(toast.errors[0].message == "cannot start recorder")
    #expect(events.events == ["pause-media", "capture-start", "play-media"])
  }
}

@MainActor
private final class WorkflowStartingRecorder: RecordingCaptureStarting, @unchecked Sendable {
  var actualSampleRate: Double = 16_000
  var onAudioChunk: ((Data) -> Void)?
  var startError: Error?
  var eventLog: TestEventLog?
  var mediaClientToDeactivate: FakeMediaRemote?
  private(set) var startCalls = 0
  private(set) var resetCalls = 0

  func startRecording(to url: URL, resolvedDevice: ResolvedRecordingDevice) async throws {
    eventLog?.append("capture-start")
    startCalls += 1
    mediaClientToDeactivate?.audioActive = false
    if let startError {
      throw startError
    }
  }

  func reset() {
    resetCalls += 1
  }
}

@MainActor
private final class WorkflowModelReadiness: RecordingModelReadinessChecking, @unchecked Sendable {
  var startFailure: ModelReadinessFailure?

  init(startFailure: ModelReadinessFailure? = nil) {
    self.startFailure = startFailure
  }

  var isReadyForRecording: Bool { startFailure == nil }
  var menuPresentation: ModelReadinessMenuPresentation {
    ModelReadinessMenuPresentation(
      title: isReadyForRecording ? "Ready" : "Loading Parakeet...",
      systemImage: "waveform",
      tone: isReadyForRecording ? .ready : .pending,
      showsProgress: !isReadyForRecording,
      retryTitle: nil
    )
  }

  func preload() {}
  func retry() {}
  func recordingStartFailure() -> ModelReadinessFailure? { startFailure }
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
private final class WorkflowToastPresenter: RecordingFeedbackPresenting, @unchecked Sendable {
  private(set) var feedback: [RecordingFeedback] = []
  var errors: [(title: String, message: String?)] {
    feedback.compactMap { presentedFeedback in
      switch presentedFeedback.event {
      case .modelReadinessBlocked(let failure):
        return (failure.title, failure.message)
      case .noInputDevice:
        return ("Recording Failed", "No audio input device available")
      case .recordingStartFailed(let message):
        return ("Recording Failed", message)
      default:
        return nil
      }
    }
  }

  func present(_ feedback: RecordingFeedback) {
    self.feedback.append(feedback)
  }

  func clearOverlayStatus() {}
}
