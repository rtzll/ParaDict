import Foundation

private struct ActiveCaptureContext {
  let recordingId: String
  var warningShown = false
  var streamingSession: ParakeetStreamingSession?
}

private struct CancelShortcutConfirmationContext {
  let hint: OverlayHint
  let task: Task<Void, Never>
}

@MainActor
private final class CaptureTransitionGate {
  private var inFlight = false

  func perform(_ operation: () async -> Void) async {
    guard !inFlight else { return }
    inFlight = true
    defer { inFlight = false }
    await operation()
  }

  func reset() {
    inFlight = false
  }
}

@MainActor
final class RecordingSessionRuntime: Sendable {
  private var activeCaptureContext: ActiveCaptureContext?
  private var sessionStateMachine = RecordingSessionStateMachine()
  private let captureTransitionGate = CaptureTransitionGate()
  private var cancelShortcutConfirmationContext: CancelShortcutConfirmationContext?
  private let cancelShortcutConfirmationWindow: TimeInterval

  init(cancelShortcutConfirmationWindow: TimeInterval = 1.5) {
    self.cancelShortcutConfirmationWindow = cancelShortcutConfirmationWindow
  }

  var recordingState: RecordingSessionState { sessionStateMachine.state }
  var overlayHint: OverlayHint? { cancelShortcutConfirmationContext?.hint }
  var currentRecordingId: String? { activeCaptureContext?.recordingId }
  var isCancelShortcutArmed: Bool { cancelShortcutConfirmationContext != nil }
  var hasShownDurationWarning: Bool { activeCaptureContext?.warningShown == true }

  func markDurationWarningShown() {
    guard var context = activeCaptureContext else { return }
    context.warningShown = true
    activeCaptureContext = context
  }

  func beginActiveCapture(recordingId: String) {
    activeCaptureContext = ActiveCaptureContext(recordingId: recordingId)
  }

  func clearActiveCapture() {
    activeCaptureContext = nil
  }

  func setActiveStreamingSession(_ session: ParakeetStreamingSession?) {
    guard var context = activeCaptureContext else { return }
    context.streamingSession = session
    activeCaptureContext = context
  }

  func takeActiveStreamingSession() -> ParakeetStreamingSession? {
    guard var context = activeCaptureContext else { return nil }
    let session = context.streamingSession
    context.streamingSession = nil
    activeCaptureContext = context
    return session
  }

  func performTransition(_ operation: () async -> Void) async {
    await captureTransitionGate.perform(operation)
  }

  func resetTransitionGate() {
    captureTransitionGate.reset()
  }

  @discardableResult
  func beginStarting() -> Bool {
    sessionStateMachine.beginStarting()
  }

  @discardableResult
  func markRecordingStarted() -> Bool {
    sessionStateMachine.markRecordingStarted()
  }

  @discardableResult
  func markStartFailed() -> Bool {
    sessionStateMachine.markStartFailed()
  }

  @discardableResult
  func beginProcessing() -> Bool {
    sessionStateMachine.beginProcessing()
  }

  @discardableResult
  func finishRecordingCancellation() -> Bool {
    sessionStateMachine.finishRecordingCancellation()
  }

  @discardableResult
  func finishProcessing() -> Bool {
    sessionStateMachine.finishProcessing()
  }

  @discardableResult
  func resetAfterInterruption() -> Bool {
    sessionStateMachine.resetAfterInterruption()
  }

  func forceStateForTesting(_ state: RecordingSessionState) {
    sessionStateMachine = RecordingSessionStateMachine(state: state)
  }

  func armCancelShortcut() {
    cancelShortcutConfirmationContext?.task.cancel()
    let hint = OverlayHint(message: "Press Esc again to discard")
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .seconds(self.cancelShortcutConfirmationWindow))
      self.clearPendingCancelShortcut()
    }
    cancelShortcutConfirmationContext = CancelShortcutConfirmationContext(hint: hint, task: task)
  }

  func clearPendingCancelShortcut() {
    cancelShortcutConfirmationContext?.task.cancel()
    cancelShortcutConfirmationContext = nil
  }

  #if DEBUG
    /// Awaits the scheduled auto-expiry of the cancel-shortcut hint. Lets tests
    /// assert post-expiry state without relying on wall-clock sleeps.
    func awaitCancelShortcutExpiryForTesting() async {
      await cancelShortcutConfirmationContext?.task.value
    }
  #endif
}
