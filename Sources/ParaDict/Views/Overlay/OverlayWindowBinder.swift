import AppKit

/// Drives the cursor-anchored overlay window from the overlay view model.
/// Re-registers Observation tracking after every change so the overlay
/// stays in sync without an explicit subscription.
@MainActor
final class OverlayWindowBinder {
  private let viewModel: OverlayViewModel
  private let windowController: CursorOverlayWindowController

  init(viewModel: OverlayViewModel, windowController: CursorOverlayWindowController) {
    self.viewModel = viewModel
    self.windowController = windowController
  }

  func start() {
    observe()
  }

  private func observe() {
    withObservationTracking {
      _ = self.viewModel.snapshot
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        windowController.update(viewModel.snapshot)
        observe()
      }
    }
  }
}
