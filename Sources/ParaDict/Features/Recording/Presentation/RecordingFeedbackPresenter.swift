import Foundation
import UserNotifications

struct RecordingFeedback: Equatable, Sendable {
  enum Event: Equatable, Sendable {
    case modelReadinessBlocked(ModelReadinessFailure)
    case noInputDevice
    case microphoneFallbackToSystemDefault
    case recordingStartFailed(String)
    case livePreviewUnavailable
    case recordingCanceled
    case recordingInterrupted(String)
    case emptyTranscription
    case transcriptionFailed(String)
    case recordingLimitWarning(remainingSeconds: Int)
  }

  let event: Event

  init(_ event: Event) {
    self.event = event
  }
}

@MainActor
protocol RecordingFeedbackPresenting: AnyObject {
  func present(_ feedback: RecordingFeedback)
  func clearOverlayStatus()
}

@MainActor
final class RecordingFeedbackPresenter: Sendable, RecordingFeedbackPresenting {
  private let toast: ToastPresenting
  private let overlayStatusPresenter: OverlayStatusPresenter

  init(
    toast: ToastPresenting,
    onOverlayStatusChange: @escaping @MainActor (OverlayStatus?) -> Void
  ) {
    self.toast = toast
    self.overlayStatusPresenter = OverlayStatusPresenter(onStatusChange: onOverlayStatusChange)
  }

  func present(_ feedback: RecordingFeedback) {
    switch feedback.event {
    case .modelReadinessBlocked(let failure):
      showCursorError(title: failure.title, message: failure.message)
    case .noInputDevice:
      showCursorError(title: "Recording Failed", message: "No audio input device available")
    case .microphoneFallbackToSystemDefault:
      showTopLevelToast(
        ToastMessage(
          type: .warning,
          title: "Mic Unavailable",
          message: "Selected mic not found, using system default"
        ))
    case .recordingStartFailed(let message):
      showCursorError(title: "Recording Failed", message: message)
    case .livePreviewUnavailable:
      showOverlayStatus(
        OverlayStatus(
          kind: .warning,
          title: "Live Preview Unavailable",
          message: "Recording will continue without transcript preview."
        ),
        duration: 2.2
      )
    case .recordingCanceled:
      showOverlayStatus(
        OverlayStatus(
          kind: .warning,
          title: "Recording Canceled",
          message: "Discarded the current recording."
        )
      )
    case .recordingInterrupted(let message):
      showOverlayStatus(
        OverlayStatus(
          kind: .error,
          title: "Recording Failed",
          message: message
        ),
        duration: 2.2
      )
    case .emptyTranscription:
      showOverlayStatus(
        OverlayStatus(
          kind: .error,
          title: "Empty Transcription",
          message: "No speech detected in recording."
        ),
        duration: 2.2
      )
    case .transcriptionFailed(let message):
      showOverlayStatus(
        OverlayStatus(
          kind: .error,
          title: "Transcription Failed",
          message: message
        ),
        duration: 2.2
      )
    case .recordingLimitWarning(let remainingSeconds):
      showTopLevelToast(
        ToastMessage(
          type: .warning,
          title: "Recording Limit",
          message:
            "Recording will stop in \(remainingSeconds / 60) min \(remainingSeconds % 60) sec"
        ))
      showRecordingLimitNotification()
    }
  }

  func clearOverlayStatus() {
    overlayStatusPresenter.clear()
  }

  private func showCursorError(title: String, message: String?) {
    toast.show(
      ToastMessage(type: .error, title: title, message: message),
      anchor: .cursor()
    )
  }

  private func showTopLevelToast(_ message: ToastMessage) {
    toast.show(message, anchor: .topCenter)
  }

  private func showOverlayStatus(_ status: OverlayStatus, duration: TimeInterval = 1.4) {
    overlayStatusPresenter.show(status, duration: duration)
  }

  private func showRecordingLimitNotification() {
    let content = UNMutableNotificationContent()
    content.title = "Recording Limit"
    content.body = "Recording will automatically stop in ~2 minutes"
    let request = UNNotificationRequest(
      identifier: "recording-warning",
      content: content,
      trigger: nil
    )
    Task {
      try? await UNUserNotificationCenter.current().add(request)
    }
  }
}
