import Foundation

@MainActor
protocol RecordingCaptureStarting: AnyObject {
  var actualSampleRate: Double { get }
  var onAudioChunk: ((Data) -> Void)? { get set }
  func startRecording(to url: URL, resolvedDevice: ResolvedRecordingDevice) async throws
  func reset()
}

@MainActor
protocol RecordingCapturePreparing: AnyObject {
  func preparePendingSession(recordingId: String) -> RecordingSessionPreparationOutcome
  func startStreamingPreview(
    for session: PendingRecordingSession,
    inputSampleRate: Double,
    onPartialTranscript: @escaping @MainActor (String) -> Void
  ) async -> Result<Void, Error>
}

@MainActor
final class RecordingCaptureStartWorkflow: Sendable {
  struct Callbacks: Sendable {
    let isModelLoaded: @MainActor () -> Bool
    let clearOverlayStatus: @MainActor () -> Void
    let startDurationChecks: @MainActor () -> Void
    let onPartialTranscript: @MainActor (String) -> Void
    let onPreviewStartupFailure: @MainActor () -> Void
    let onRecordingStarted: @MainActor () -> Void
  }

  private let recorder: RecordingCaptureStarting
  private let mediaPlayback: MediaPlaybackController
  private let sessionRuntime: RecordingSessionRuntime
  private let capturePreparationWorkflow: RecordingCapturePreparing
  private let toast: ToastPresenting
  private let callbacks: Callbacks

  init(
    recorder: RecordingCaptureStarting,
    mediaPlayback: MediaPlaybackController,
    sessionRuntime: RecordingSessionRuntime,
    capturePreparationWorkflow: RecordingCapturePreparing,
    toast: ToastPresenting,
    callbacks: Callbacks
  ) {
    self.recorder = recorder
    self.mediaPlayback = mediaPlayback
    self.sessionRuntime = sessionRuntime
    self.capturePreparationWorkflow = capturePreparationWorkflow
    self.toast = toast
    self.callbacks = callbacks
  }

  func startRecording() async {
    guard canStartRecording() else { return }

    guard let session = preparePendingRecordingSession() else {
      return
    }

    guard await beginRecordingCapture(for: session) else {
      return
    }

    await startStreamingPreview(for: session)
  }

  private func canStartRecording() -> Bool {
    guard sessionRuntime.beginStarting() else { return false }
    guard callbacks.isModelLoaded() else {
      sessionRuntime.markStartFailed()
      toast.showError(
        title: "Model Not Ready",
        message: "Please wait for Parakeet to finish loading."
      )
      return false
    }
    return true
  }

  private func preparePendingRecordingSession() -> PendingRecordingSession? {
    let recordingId = Recording.generateId()
    sessionRuntime.beginActiveCapture(recordingId: recordingId)
    sessionRuntime.clearPendingCancelShortcut()

    let preparation = capturePreparationWorkflow.preparePendingSession(recordingId: recordingId)

    guard case .ready(let preparedSession) = preparation else {
      toast.showError(title: "Recording Failed", message: "No audio input device available")
      recorder.reset()
      sessionRuntime.clearActiveCapture()
      sessionRuntime.markStartFailed()
      return nil
    }

    if preparedSession.didFallbackToSystemDefault {
      toast.show(
        ToastMessage(
          type: .warning,
          title: "Mic Unavailable",
          message: "Selected mic not found, using system default"
        ))
    }

    callbacks.onPartialTranscript("")
    recorder.onAudioChunk = { data in
      preparedSession.session.streamingSession.send(data)
    }

    return preparedSession.session
  }

  private func beginRecordingCapture(for session: PendingRecordingSession) async -> Bool {
    do {
      try await recorder.startRecording(
        to: session.audioURL,
        resolvedDevice: session.resolvedDevice
      )
      callbacks.clearOverlayStatus()
      callbacks.startDurationChecks()
      mediaPlayback.pauseMedia()
      sessionRuntime.markRecordingStarted()
      callbacks.onRecordingStarted()
      return true
    } catch {
      toast.showError(title: "Recording Failed", message: error.localizedDescription)
      recorder.reset()
      sessionRuntime.clearActiveCapture()
      sessionRuntime.markStartFailed()
      callbacks.onPartialTranscript("")
      recorder.onAudioChunk = nil
      await session.streamingSession.cancel()
      return false
    }
  }

  private func startStreamingPreview(for session: PendingRecordingSession) async {
    let result = await capturePreparationWorkflow.startStreamingPreview(
      for: session,
      inputSampleRate: recorder.actualSampleRate
    ) { [callbacks] text in
      callbacks.onPartialTranscript(text)
    }

    switch result {
    case .success:
      sessionRuntime.setActiveStreamingSession(session.streamingSession)
    case .failure:
      sessionRuntime.setActiveStreamingSession(nil)
      callbacks.onPreviewStartupFailure()
    }
  }
}

extension AudioRecorder: RecordingCaptureStarting {}
extension RecordingCapturePreparationWorkflow: RecordingCapturePreparing {}
