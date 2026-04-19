import Foundation

@MainActor
final class RecordingSessionFlowController: Sendable {
  struct Callbacks: Sendable {
    let stopDurationChecks: @MainActor () -> Void
    let clearRecordingPresentation: @MainActor () -> Void
    let onRecordingEnded: @MainActor () -> Void
    let onCancelComplete: @MainActor (URL?) -> Void
    let transcribe: @MainActor (CompletedRecordingCapture) async -> Void
  }

  private let recorder: AudioRecorder
  private let sessionRuntime: RecordingSessionRuntime
  private let mediaPlayback: MediaPlaybackController
  private let toast: ToastPresenting
  private let captureStartWorkflow: RecordingCaptureStartWorkflow
  private let captureShutdownWorkflow: RecordingCaptureShutdownWorkflow
  private let callbacks: Callbacks

  init(
    recorder: AudioRecorder,
    sessionRuntime: RecordingSessionRuntime,
    mediaPlayback: MediaPlaybackController,
    toast: ToastPresenting,
    captureStartWorkflow: RecordingCaptureStartWorkflow,
    captureShutdownWorkflow: RecordingCaptureShutdownWorkflow,
    callbacks: Callbacks
  ) {
    self.recorder = recorder
    self.sessionRuntime = sessionRuntime
    self.mediaPlayback = mediaPlayback
    self.toast = toast
    self.captureStartWorkflow = captureStartWorkflow
    self.captureShutdownWorkflow = captureShutdownWorkflow
    self.callbacks = callbacks
  }

  func start() async {
    await sessionRuntime.performTransition {
      guard sessionRuntime.recordingState == .idle else { return }
      await captureStartWorkflow.startRecording()
    }
  }

  func stopAndTranscribe() async {
    await performEndedRecordingTransition {
      guard let capture = await captureShutdownWorkflow.stopCaptureForTranscription() else {
        return
      }

      await callbacks.transcribe(capture)
    }
  }

  func cancel() async {
    await performEndedRecordingTransition {
      let audioURL = await captureShutdownWorkflow.stopCaptureForCancellation()
      callbacks.onCancelComplete(audioURL)
    }
  }

  func handleInterruption(message: String) {
    callbacks.stopDurationChecks()
    callbacks.onRecordingEnded()
    let session = sessionRuntime.takeActiveStreamingSession()
    sessionRuntime.clearActiveCapture()
    sessionRuntime.resetAfterInterruption()
    sessionRuntime.resetTransitionGate()
    sessionRuntime.clearPendingCancelShortcut()
    callbacks.clearRecordingPresentation()
    Task { await session?.cancel() }
    toast.showError(title: "Recording Failed", message: message)
    recorder.reset()
  }

  private func performEndedRecordingTransition(_ operation: () async -> Void) async {
    await sessionRuntime.performTransition {
      guard sessionRuntime.recordingState == .recording else { return }
      completeActiveRecordingSession()
      await operation()
    }
  }

  private func completeActiveRecordingSession(resumeMedia: Bool = true) {
    sessionRuntime.clearPendingCancelShortcut()
    callbacks.stopDurationChecks()
    if resumeMedia {
      mediaPlayback.resumeIfPaused()
    }
    callbacks.onRecordingEnded()
  }
}
