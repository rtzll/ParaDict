import Testing

@testable import ParaDict

@MainActor
struct RecordingSessionRuntimeTests {
  @Test func activeCaptureTracksRecordingMetadata() {
    let runtime = RecordingSessionRuntime()

    runtime.beginActiveCapture(recordingId: "recording-123")

    #expect(runtime.currentRecordingId == "recording-123")
    #expect(!runtime.hasShownDurationWarning)

    runtime.markDurationWarningShown()

    #expect(runtime.hasShownDurationWarning)

    runtime.clearActiveCapture()

    #expect(runtime.currentRecordingId == nil)
    #expect(!runtime.hasShownDurationWarning)
  }

  @Test func cancelShortcutHintArmsAndExpires() async {
    let runtime = RecordingSessionRuntime(cancelShortcutConfirmationWindow: 0.01)

    runtime.armCancelShortcut()

    #expect(runtime.isCancelShortcutArmed)
    #expect(runtime.overlayHint?.message == "Press Esc again to discard")

    await runtime.awaitCancelShortcutExpiryForTesting()

    #expect(!runtime.isCancelShortcutArmed)
    #expect(runtime.overlayHint == nil)
  }
}
