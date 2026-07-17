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
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) async -> Result<Void, Error>
}

enum RecordingCaptureStartOutcome: Equatable, Sendable {
  case started
  case notStarted
}

@MainActor
final class RecordingCaptureStartWorkflow: Sendable {
  private let recorder: RecordingCaptureStarting
  private let mediaPlayback: MediaPlaybackController
  private let sessionRuntime: RecordingSessionRuntime
  private let modelReadiness: RecordingModelReadinessChecking
  private let capturePreparationWorkflow: RecordingCapturePreparing
  private let feedbackPresenter: RecordingFeedbackPresenting

  init(
    recorder: RecordingCaptureStarting,
    mediaPlayback: MediaPlaybackController,
    sessionRuntime: RecordingSessionRuntime,
    modelReadiness: RecordingModelReadinessChecking,
    capturePreparationWorkflow: RecordingCapturePreparing,
    feedbackPresenter: RecordingFeedbackPresenting
  ) {
    self.recorder = recorder
    self.mediaPlayback = mediaPlayback
    self.sessionRuntime = sessionRuntime
    self.modelReadiness = modelReadiness
    self.capturePreparationWorkflow = capturePreparationWorkflow
    self.feedbackPresenter = feedbackPresenter
  }

  func startRecording(
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) async -> RecordingCaptureStartOutcome {
    guard canStartRecording() else { return .notStarted }

    guard let session = preparePendingRecordingSession(onPreviewUpdate: onPreviewUpdate) else {
      return .notStarted
    }

    guard await beginRecordingCapture(for: session, onPreviewUpdate: onPreviewUpdate) else {
      return .notStarted
    }

    await startStreamingPreview(for: session, onPreviewUpdate: onPreviewUpdate)
    return .started
  }

  private func canStartRecording() -> Bool {
    guard sessionRuntime.beginStarting() else { return false }
    if let failure = modelReadiness.recordingStartFailure() {
      sessionRuntime.markStartFailed()
      feedbackPresenter.present(.init(.modelReadinessBlocked(failure)))
      return false
    }
    return true
  }

  private func preparePendingRecordingSession(
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) -> PendingRecordingSession? {
    let recordingId = Recording.generateId()
    sessionRuntime.beginActiveCapture(recordingId: recordingId)
    sessionRuntime.clearPendingCancelShortcut()

    let preparation = capturePreparationWorkflow.preparePendingSession(recordingId: recordingId)

    guard case .ready(let preparedSession) = preparation else {
      feedbackPresenter.present(.init(.noInputDevice))
      recorder.reset()
      sessionRuntime.clearActiveCapture()
      sessionRuntime.markStartFailed()
      return nil
    }

    if preparedSession.didFallbackToSystemDefault {
      feedbackPresenter.present(.init(.microphoneFallbackToSystemDefault))
    }

    onPreviewUpdate(.reset)
    recorder.onAudioChunk = { data in
      preparedSession.session.streamingSession.send(data)
    }

    return preparedSession.session
  }

  private func beginRecordingCapture(
    for session: PendingRecordingSession,
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) async -> Bool {
    mediaPlayback.prepareForRecording()

    do {
      try await recorder.startRecording(
        to: session.audioURL,
        resolvedDevice: session.resolvedDevice
      )
      feedbackPresenter.clearOverlayStatus()
      sessionRuntime.markRecordingStarted()
      return true
    } catch {
      await mediaPlayback.restoreAfterRecording()
      feedbackPresenter.present(.init(.recordingStartFailed(error.localizedDescription)))
      recorder.reset()
      sessionRuntime.clearActiveCapture()
      sessionRuntime.markStartFailed()
      onPreviewUpdate(.reset)
      recorder.onAudioChunk = nil
      await session.streamingSession.cancel()
      return false
    }
  }

  private func startStreamingPreview(
    for session: PendingRecordingSession,
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) async {
    let result = await capturePreparationWorkflow.startStreamingPreview(
      for: session,
      inputSampleRate: recorder.actualSampleRate
    ) { update in
      onPreviewUpdate(update)
    }

    switch result {
    case .success:
      sessionRuntime.setActiveStreamingSession(session.streamingSession)
    case .failure:
      sessionRuntime.setActiveStreamingSession(nil)
      recorder.onAudioChunk = nil
      onPreviewUpdate(.reset)
      feedbackPresenter.present(.init(.livePreviewUnavailable))
    }
  }
}

extension AudioRecorder: RecordingCaptureStarting {}
extension RecordingCapturePreparationWorkflow: RecordingCapturePreparing {}
