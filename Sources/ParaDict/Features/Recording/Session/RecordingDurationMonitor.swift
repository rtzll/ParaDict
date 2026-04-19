import Foundation

@MainActor
final class RecordingDurationMonitor: Sendable {
  private let maximumDuration: TimeInterval
  private let warningDuration: TimeInterval
  private let currentDuration: () -> TimeInterval
  private let hasShownWarning: () -> Bool
  private let markWarningShown: () -> Void
  private let onWarning: (Int) -> Void
  private let onLimitReached: () -> Void
  private var timer: Timer?

  init(
    maximumDuration: TimeInterval,
    warningDuration: TimeInterval,
    currentDuration: @escaping () -> TimeInterval,
    hasShownWarning: @escaping () -> Bool,
    markWarningShown: @escaping () -> Void,
    onWarning: @escaping (Int) -> Void,
    onLimitReached: @escaping () -> Void
  ) {
    self.maximumDuration = maximumDuration
    self.warningDuration = warningDuration
    self.currentDuration = currentDuration
    self.hasShownWarning = hasShownWarning
    self.markWarningShown = markWarningShown
    self.onWarning = onWarning
    self.onLimitReached = onLimitReached
  }

  func start() {
    stop()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.evaluateCurrentDuration()
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func evaluateCurrentDuration() {
    let duration = currentDuration()

    if duration >= warningDuration && !hasShownWarning() {
      markWarningShown()
      let remainingSeconds = max(0, Int(maximumDuration - duration))
      onWarning(remainingSeconds)
    }

    if duration >= maximumDuration {
      onLimitReached()
    }
  }
}
