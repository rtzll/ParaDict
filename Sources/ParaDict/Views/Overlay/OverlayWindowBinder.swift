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
      _ = self.viewModel.state
      _ = self.viewModel.duration
      _ = self.viewModel.meterLevel
      _ = self.viewModel.partialTranscript
      _ = self.viewModel.overlayStatus
      _ = self.viewModel.overlayHint
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        windowController.update(
          state: viewModel.state,
          duration: viewModel.duration,
          meterLevel: viewModel.meterLevel,
          partialTranscript: viewModel.partialTranscript,
          overlayStatus: viewModel.overlayStatus,
          overlayHint: viewModel.overlayHint
        )
        observe()
      }
    }
  }
}
