@MainActor
final class HotkeyDelegateImpl: HotkeyManagerDelegate {
  private weak var recordingController: RecordingController?

  init(recordingController: RecordingController) {
    self.recordingController = recordingController
  }

  nonisolated func hotkeyDidToggleRecording() {
    Task { @MainActor in
      self.recordingController?.toggleRecording()
    }
  }

  nonisolated func hotkeyDidCancelRecording() {
    Task { @MainActor in
      self.recordingController?.handleCancelRecordingShortcut()
    }
  }
}
