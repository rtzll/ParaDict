import AppKit

/// Drives the status item image from the recording controller's state and
/// mic meter level. Re-registers Observation tracking after every change so
/// the icon stays in sync without an explicit subscription.
@MainActor
final class MenuBarIconBinder {
  private let statusItem: NSStatusItem
  private let recordingController: RecordingController

  init(statusItem: NSStatusItem, recordingController: RecordingController) {
    self.statusItem = statusItem
    self.recordingController = recordingController
  }

  func start() {
    observe()
    updateIcon()
  }

  private func observe() {
    withObservationTracking {
      _ = self.recordingController.displayState
      _ = self.recordingController.recorder.meterLevel
    } onChange: {
      Task { @MainActor [weak self] in
        self?.updateIcon()
        self?.observe()
      }
    }
  }

  private func updateIcon() {
    statusItem.button?.image = MenuBarIconRenderer.render(
      state: recordingController.displayState,
      meterLevel: recordingController.recorder.meterLevel
    )
  }
}
