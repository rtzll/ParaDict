import Foundation

@MainActor
final class OverlayStatusPresenter: Sendable {
  private var dismissalTask: Task<Void, Never>?
  private let onStatusChange: @MainActor (OverlayStatus?) -> Void

  init(onStatusChange: @escaping @MainActor (OverlayStatus?) -> Void) {
    self.onStatusChange = onStatusChange
  }

  func show(_ status: OverlayStatus, duration: TimeInterval = 1.4) {
    dismissalTask?.cancel()
    onStatusChange(status)
    dismissalTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(duration))
      guard let self else { return }
      self.dismissalTask = nil
      self.onStatusChange(nil)
    }
  }

  func clear() {
    dismissalTask?.cancel()
    dismissalTask = nil
    onStatusChange(nil)
  }

  #if DEBUG
    /// Awaits the scheduled dismissal task. Lets tests assert post-dismissal
    /// state without racing a wall-clock sleep against the duration window.
    func awaitPendingDismissalForTesting() async {
      await dismissalTask?.value
    }
  #endif
}
