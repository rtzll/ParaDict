import Foundation

enum RecordingSessionFlowEvent: Sendable {
  case recordingStarted
  case recordingEnded
  case previewUpdate(StreamingPreviewUpdate)
  case transcriptionRequested(CompletedRecordingCapture)
  case overlayHintChanged(OverlayHint?)
}

@MainActor
final class RecordingSession: Sendable {
  struct Callbacks: Sendable {
    let handleEvent: @MainActor (RecordingSessionFlowEvent) -> Void
  }

  private let recorder: AudioRecorder
  private let sessionRuntime: RecordingSessionRuntime
  private let mediaPlayback: MediaPlaybackController
  private let captureStartWorkflow: RecordingCaptureStartWorkflow
  private let captureShutdownWorkflow: RecordingCaptureShutdownWorkflow
  private let feedbackPresenter: RecordingFeedbackPresenting
  private let maximumDuration: TimeInterval
  private let warningDuration: TimeInterval
  private let callbacks: Callbacks

  private lazy var durationMonitor = RecordingDurationMonitor(
    maximumDuration: maximumDuration,
    warningDuration: warningDuration,
    currentDuration: { [weak self] in self?.recorder.currentDuration ?? 0 },
    hasShownWarning: { [weak self] in self?.sessionRuntime.hasShownDurationWarning ?? false },
    markWarningShown: { [weak self] in self?.sessionRuntime.markDurationWarningShown() },
    onWarning: { [weak self] remainingSeconds in
      self?.feedbackPresenter.present(
        .init(.recordingLimitWarning(remainingSeconds: remainingSeconds)))
    },
    onLimitReached: { [weak self] in
      Task { @MainActor [weak self] in
        await self?.stopAndTranscribe()
      }
    }
  )

  init(
    recorder: AudioRecorder,
    deviceManager: AudioDeviceManager,
    mediaPlayback: MediaPlaybackController,
    transcriptionProvider: TranscriptionProviding,
    modelReadiness: RecordingModelReadinessChecking,
    feedbackPresenter: RecordingFeedbackPresenting,
    maximumDuration: TimeInterval,
    warningDuration: TimeInterval,
    clearRecordingPresentation: @escaping @MainActor () -> Void,
    clearOverlayStatus: @escaping @MainActor () -> Void,
    callbacks: Callbacks
  ) {
    let sessionRuntime = RecordingSessionRuntime { hint in
      callbacks.handleEvent(.overlayHintChanged(hint))
    }
    let capturePreparationWorkflow = RecordingCapturePreparationWorkflow(
      deviceResolver: deviceManager,
      modelProvider: transcriptionProvider
    )
    let captureStartWorkflow = RecordingCaptureStartWorkflow(
      recorder: recorder,
      mediaPlayback: mediaPlayback,
      sessionRuntime: sessionRuntime,
      modelReadiness: modelReadiness,
      capturePreparationWorkflow: capturePreparationWorkflow,
      feedbackPresenter: feedbackPresenter
    )
    let captureShutdownWorkflow = RecordingCaptureShutdownWorkflow(
      recorder: recorder,
      mediaPlayback: mediaPlayback,
      sessionRuntime: sessionRuntime,
      clearRecordingPresentation: clearRecordingPresentation,
      clearOverlayStatus: clearOverlayStatus
    )

    self.recorder = recorder
    self.sessionRuntime = sessionRuntime
    self.mediaPlayback = mediaPlayback
    self.captureStartWorkflow = captureStartWorkflow
    self.captureShutdownWorkflow = captureShutdownWorkflow
    self.feedbackPresenter = feedbackPresenter
    self.maximumDuration = maximumDuration
    self.warningDuration = warningDuration
    self.callbacks = callbacks
  }

  var state: RecordingSessionState { sessionRuntime.recordingState }

  func handleCancelShortcut() {
    guard state == .recording else { return }

    if sessionRuntime.isCancelShortcutArmed {
      sessionRuntime.clearPendingCancelShortcut()
      Task { await cancel() }
    } else {
      sessionRuntime.armCancelShortcut()
    }
  }

  func finishProcessing() {
    sessionRuntime.finishProcessing()
  }

  func start() async {
    await sessionRuntime.performTransition {
      guard sessionRuntime.recordingState == .idle else { return }
      let outcome = await captureStartWorkflow.startRecording { [weak self] update in
        self?.callbacks.handleEvent(.previewUpdate(update))
      }
      guard case .started = outcome else { return }
      durationMonitor.start()
      callbacks.handleEvent(.recordingStarted)
    }
  }

  func stopAndTranscribe() async {
    await performEndedRecordingTransition {
      guard let capture = await captureShutdownWorkflow.stopCaptureForTranscription() else {
        return
      }

      callbacks.handleEvent(.transcriptionRequested(capture))
    }
  }

  func cancel() async {
    await performEndedRecordingTransition {
      let audioURL = await captureShutdownWorkflow.stopCaptureForCancellation()
      feedbackPresenter.present(.init(.recordingCanceled))
      if let audioURL {
        try? FileManager.default.removeItem(at: audioURL)
      }
    }
  }

  func handleInterruption(message: String) {
    durationMonitor.stop()
    callbacks.handleEvent(.recordingEnded)
    let session = sessionRuntime.takeActiveStreamingSession()
    sessionRuntime.clearActiveCapture()
    sessionRuntime.resetAfterInterruption()
    sessionRuntime.resetTransitionGate()
    sessionRuntime.clearPendingCancelShortcut()
    callbacks.handleEvent(.previewUpdate(.reset))
    feedbackPresenter.clearOverlayStatus()
    Task { [mediaPlayback] in
      await session?.cancel()
      await mediaPlayback.restoreAfterRecording()
    }
    feedbackPresenter.present(.init(.recordingInterrupted(message)))
    recorder.reset()
  }

  private func performEndedRecordingTransition(_ operation: () async -> Void) async {
    await sessionRuntime.performTransition {
      guard sessionRuntime.recordingState == .recording else { return }
      completeActiveRecordingSession()
      await operation()
    }
  }

  private func completeActiveRecordingSession() {
    sessionRuntime.clearPendingCancelShortcut()
    durationMonitor.stop()
    callbacks.handleEvent(.recordingEnded)
  }

  #if DEBUG
    func forceStateForTesting(_ state: RecordingSessionState) {
      sessionRuntime.forceStateForTesting(state)
    }
  #endif
}
