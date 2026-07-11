import AppKit
@preconcurrency import FluidAudio
import Foundation
import Observation

@Observable
@MainActor
final class RecordingController: Sendable {
  let recorder: AudioRecorder
  let deviceManager: AudioDeviceManager
  let toast: ToastPresenting
  private let mediaPlayback: MediaPlaybackController
  private let transcriptionProvider: TranscriptionProviding
  private let modelReadiness: RecordingModelReadinessChecking
  private let recordingHistory: RecordingHistoryWriting
  private let pasteboardWriter: PasteboardWriting
  private let sessionRuntime: RecordingSessionRuntime
  @ObservationIgnored
  private var streamingTranscriptAccumulator = StreamingTranscriptAccumulator()
  var partialTranscript = ""
  var overlayStatus: OverlayStatus?
  var overlayHint: OverlayHint? { sessionRuntime.overlayHint }

  let maxRecordingDuration: TimeInterval = 600.0
  var warningDuration: TimeInterval { maxRecordingDuration * 0.8 }

  @ObservationIgnored
  private var feedbackPresenter: RecordingFeedbackPresenter!
  @ObservationIgnored
  private var transcriptionWorkflow: RecordingTranscriptionWorkflow!
  @ObservationIgnored
  private var capturePreparationWorkflow: RecordingCapturePreparationWorkflow!
  @ObservationIgnored
  private var captureShutdownWorkflow: RecordingCaptureShutdownWorkflow!
  @ObservationIgnored
  private var captureStartWorkflow: RecordingCaptureStartWorkflow!
  @ObservationIgnored
  private var recordingSessionFlowController: RecordingSessionFlowController!

  var onRecordingStarted: (() -> Void)?
  var onRecordingEnded: (() -> Void)?

  var recordingSessionState: RecordingSessionState { sessionRuntime.recordingState }
  var displayState: RecordingState {
    if case .error(let message) = recorder.state {
      return .error(message)
    }

    switch recordingSessionState {
    case .idle, .starting:
      return .idle
    case .recording:
      return .recording
    case .processing:
      return .processing
    }
  }

  init(
    recorder: AudioRecorder = AudioRecorder(),
    deviceManager: AudioDeviceManager = AudioDeviceManager(),
    mediaPlayback: MediaPlaybackController = MediaPlaybackController(),
    sessionRuntime: RecordingSessionRuntime = RecordingSessionRuntime(),
    toast: ToastPresenting = ToastWindowController.shared,
    transcriptionProvider: TranscriptionProviding,
    modelReadiness: RecordingModelReadinessChecking? = nil,
    recordingHistory: RecordingHistoryWriting,
    pasteboardWriter: PasteboardWriting
  ) {
    self.recorder = recorder
    self.deviceManager = deviceManager
    self.mediaPlayback = mediaPlayback
    self.sessionRuntime = sessionRuntime
    self.toast = toast
    self.transcriptionProvider = transcriptionProvider
    self.modelReadiness =
      modelReadiness ?? TranscriptionModelReadiness(provider: transcriptionProvider)
    self.recordingHistory = recordingHistory
    self.pasteboardWriter = pasteboardWriter
    recorder.onRecordingInterrupted = { [weak self] message in
      self?.handleRecordingInterrupted(message: message)
    }
    feedbackPresenter = RecordingFeedbackPresenter(toast: toast) { [weak self] status in
      self?.overlayStatus = status
    }
    transcriptionWorkflow = RecordingTranscriptionWorkflow(
      provider: transcriptionProvider,
      recordingHistory: recordingHistory,
      pasteboardWriter: pasteboardWriter
    )
    capturePreparationWorkflow = RecordingCapturePreparationWorkflow(
      deviceResolver: deviceManager,
      modelProvider: transcriptionProvider
    )
    captureStartWorkflow = RecordingCaptureStartWorkflow(
      recorder: recorder,
      mediaPlayback: mediaPlayback,
      sessionRuntime: sessionRuntime,
      modelReadiness: self.modelReadiness,
      capturePreparationWorkflow: capturePreparationWorkflow,
      feedbackPresenter: feedbackPresenter
    )
    captureShutdownWorkflow = RecordingCaptureShutdownWorkflow(
      recorder: recorder,
      sessionRuntime: sessionRuntime,
      clearRecordingPresentation: { [weak self] in self?.clearRecordingPresentation() },
      clearOverlayStatus: { [weak self] in self?.clearOverlayStatus() }
    )
    recordingSessionFlowController = RecordingSessionFlowController(
      recorder: recorder,
      sessionRuntime: sessionRuntime,
      mediaPlayback: mediaPlayback,
      captureStartWorkflow: captureStartWorkflow,
      captureShutdownWorkflow: captureShutdownWorkflow,
      feedbackPresenter: feedbackPresenter,
      maximumDuration: maxRecordingDuration,
      warningDuration: warningDuration,
      callbacks: RecordingSessionFlowController.Callbacks(
        handleEvent: { [weak self] event in
          self?.handleSessionFlowEvent(event)
        }
      )
    )
  }

  var isModelLoaded: Bool { modelReadiness.isReadyForRecording }
  var isModelLoading: Bool { modelReadiness.menuPresentation.showsProgress }
  var modelReadinessPresentation: ModelReadinessMenuPresentation {
    modelReadiness.menuPresentation
  }

  func preloadModel() {
    modelReadiness.preload()
  }

  func retryModelLoading() {
    modelReadiness.retry()
  }

  func toggleRecording() {
    if recordingSessionState == .recording {
      stopAndTranscribe()
    } else {
      startRecording()
    }
  }

  func startRecording() {
    Task { await recordingSessionFlowController.start() }
  }

  func stopAndTranscribe() {
    Task { await recordingSessionFlowController.stopAndTranscribe() }
  }

  func cancelRecording() {
    Task { await recordingSessionFlowController.cancel() }
  }

  func handleCancelRecordingShortcut() {
    guard recordingSessionState == .recording else { return }

    if sessionRuntime.isCancelShortcutArmed {
      sessionRuntime.clearPendingCancelShortcut()
      cancelRecording()
      return
    }

    sessionRuntime.armCancelShortcut()
  }

  func transcribe(_ capture: CompletedRecordingCapture) async {
    let outcome = await transcriptionWorkflow.process(capture)

    performIfProcessingCaptureActive {
      handleTranscriptionOutcome(outcome)
    }
  }

  func handleStreamingPreviewStartupFailure() {
    resetStreamingPreview()
    recorder.onAudioChunk = nil
    presentFeedback(.init(.livePreviewUnavailable))
  }

  private func performIfProcessingCaptureActive(_ operation: () -> Void) {
    guard recordingSessionState == .processing else { return }
    operation()
  }

  private func resetTranscriptionPresentation() {
    sessionRuntime.finishProcessing()
    clearRecordingPresentation()
    recorder.reset()
  }

  private func handleTranscriptionOutcome(_ outcome: RecordingTranscriptionOutcome) {
    resetTranscriptionPresentation()

    switch outcome {
    case .succeeded:
      return
    case .empty:
      presentFeedback(.init(.emptyTranscription))
    case .failed(let message):
      presentFeedback(.init(.transcriptionFailed(message)))
    }
  }

  private func handleRecordingInterrupted(message: String) {
    recordingSessionFlowController.handleInterruption(message: message)
  }

  private func clearRecordingPresentation() {
    resetStreamingPreview()
    clearOverlayStatus()
  }

  private func applyStreamingPreviewUpdate(_ update: StreamingPreviewUpdate) {
    if case .reset = update {
      _ = streamingTranscriptAccumulator.apply(update)
      partialTranscript = ""
      return
    }

    guard streamingTranscriptAccumulator.apply(update) else { return }
    partialTranscript = streamingTranscriptAccumulator.displayText
  }

  private func resetStreamingPreview() {
    applyStreamingPreviewUpdate(.reset)
  }

  func reloadShortcuts() {
    CustomShortcutMonitor.shared.reloadShortcuts()
  }

  private func handleSessionFlowEvent(_ event: RecordingSessionFlowEvent) {
    switch event {
    case .recordingStarted:
      onRecordingStarted?()
    case .recordingEnded:
      onRecordingEnded?()
    case .previewUpdate(let update):
      applyStreamingPreviewUpdate(update)
    case .transcriptionRequested(let capture):
      Task { [weak self] in
        await self?.transcribe(capture)
      }
    }
  }

  private func presentFeedback(_ feedback: RecordingFeedback) {
    feedbackPresenter.present(feedback)
  }

  private func clearOverlayStatus() {
    feedbackPresenter.clearOverlayStatus()
  }
}

#if DEBUG
  extension RecordingController {
    func setRecordingSessionStateForTesting(_ state: RecordingSessionState) {
      sessionRuntime.forceStateForTesting(state)
    }
  }
#endif
