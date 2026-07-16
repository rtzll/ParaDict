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
  @ObservationIgnored
  private var streamingTranscriptAccumulator = StreamingTranscriptAccumulator()
  var partialTranscript = ""
  var overlayStatus: OverlayStatus?
  var overlayHint: OverlayHint?

  let maxRecordingDuration: TimeInterval = 600.0
  var warningDuration: TimeInterval { maxRecordingDuration * 0.8 }

  @ObservationIgnored
  private var feedbackPresenter: RecordingFeedbackPresenter!
  @ObservationIgnored
  private var transcriptionWorkflow: RecordingTranscriptionWorkflow!
  @ObservationIgnored
  private var recordingSession: RecordingSession!

  var onRecordingStarted: (() -> Void)?
  var onRecordingEnded: (() -> Void)?

  var recordingSessionState: RecordingSessionState { recordingSession.state }
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
    toast: ToastPresenting = ToastWindowController.shared,
    transcriptionProvider: TranscriptionProviding,
    modelReadiness: RecordingModelReadinessChecking? = nil,
    recordingHistory: RecordingHistoryWriting,
    pasteboardWriter: PasteboardWriting
  ) {
    self.recorder = recorder
    self.deviceManager = deviceManager
    self.mediaPlayback = mediaPlayback
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
    recordingSession = RecordingSession(
      recorder: recorder,
      deviceManager: deviceManager,
      mediaPlayback: mediaPlayback,
      transcriptionProvider: transcriptionProvider,
      modelReadiness: self.modelReadiness,
      feedbackPresenter: feedbackPresenter,
      maximumDuration: maxRecordingDuration,
      warningDuration: warningDuration,
      clearRecordingPresentation: { [weak self] in self?.clearRecordingPresentation() },
      clearOverlayStatus: { [weak self] in self?.clearOverlayStatus() },
      callbacks: RecordingSession.Callbacks(
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

  var presentationSnapshot: RecordingPresentationSnapshot {
    RecordingPresentationSnapshot(
      overlay: OverlaySnapshot(
        state: displayState,
        duration: recorder.currentDuration,
        meterLevel: recorder.meterLevel,
        partialTranscript: partialTranscript,
        status: overlayStatus,
        hint: overlayHint
      ),
      modelReadiness: modelReadiness.menuPresentation,
      audioDevice: AudioDeviceSnapshot(
        inputMode: deviceManager.inputMode,
        selectedDeviceUID: deviceManager.selectedDeviceUID,
        systemDefaultDeviceName: deviceManager.systemDefaultDeviceName,
        effectiveDeviceName: deviceManager.effectiveDeviceName,
        isSelectedDeviceAvailable: deviceManager.isSelectedDeviceAvailable,
        availableDevices: deviceManager.availableDevices
      )
    )
  }

  var overlaySnapshot: OverlaySnapshot {
    presentationSnapshot.overlay
  }

  func selectDevice(_ device: AudioInputDevice) {
    deviceManager.selectDevice(device)
  }

  func selectSystemDefaultMicrophone() {
    deviceManager.selectSystemDefault()
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
    Task { await recordingSession.start() }
  }

  func stopAndTranscribe() {
    Task { await recordingSession.stopAndTranscribe() }
  }

  func cancelRecording() {
    Task { await recordingSession.cancel() }
  }

  func handleCancelRecordingShortcut() {
    recordingSession.handleCancelShortcut()
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
    recordingSession.finishProcessing()
    clearRecordingPresentation()
    recorder.reset()
  }

  private func handleTranscriptionOutcome(_ outcome: RecordingTranscriptionOutcome) {
    resetTranscriptionPresentation()

    switch outcome {
    case .succeeded:
      presentFeedback(.init(.transcriptionSucceeded))
    case .empty:
      presentFeedback(.init(.emptyTranscription))
    case .failed(let message):
      presentFeedback(.init(.transcriptionFailed(message)))
    }
  }

  private func handleRecordingInterrupted(message: String) {
    recordingSession.handleInterruption(message: message)
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
    case .overlayHintChanged(let hint):
      overlayHint = hint
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
      recordingSession.forceStateForTesting(state)
    }
  }
#endif
