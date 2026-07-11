import AppKit

/// Drives the cursor-anchored overlay window from the overlay view model.
/// Re-registers Observation tracking after every change so the overlay
/// stays in sync without an explicit subscription.
@MainActor
final class OverlayWindowBinder {
  private let recordingController: RecordingController
  private let windowController: CursorOverlayWindowController

  init(recordingController: RecordingController, windowController: CursorOverlayWindowController) {
    self.recordingController = recordingController
    self.windowController = windowController
  }

  func start() {
    observe()
  }

  private func observe() {
    withObservationTracking {
      _ = self.recordingController.overlaySnapshot
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        windowController.update(recordingController.overlaySnapshot)
        observe()
      }
    }
  }
}
