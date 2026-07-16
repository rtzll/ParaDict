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
    guard let button = statusItem.button else { return }
    let state = recordingController.displayState
    button.image = MenuBarIconRenderer.render(
      state: state,
      meterLevel: recordingController.recorder.meterLevel
    )
    button.setAccessibilityLabel("ParaDict")
    button.setAccessibilityValue(accessibilityValue(for: state))
    button.setAccessibilityHelp("Open ParaDict controls")
  }

  private func accessibilityValue(for state: RecordingState) -> String {
    switch state {
    case .idle: return "Idle"
    case .recording: return "Recording"
    case .processing: return "Transcribing"
    case .error(let message): return "Error: \(message)"
    }
  }
}
