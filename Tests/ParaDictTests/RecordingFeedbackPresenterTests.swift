import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingFeedbackPresenterTests {
  @Test func modelReadinessBlockUsesTransientCursorError() {
    let toast = FeedbackToastPresenter()
    var overlayStatus: OverlayStatus?
    let presenter = RecordingFeedbackPresenter(toast: toast) { status in
      overlayStatus = status
    }

    presenter.present(
      RecordingFeedback(
        .modelReadinessBlocked(
          ModelReadinessFailure(title: "Model Loading", message: "Please wait"))))

    #expect(toast.presented.count == 1)
    #expect(toast.presented[0].message.type == .error)
    #expect(toast.presented[0].message.title == "Model Loading")
    #expect(toast.presented[0].anchor == .cursor())
    #expect(overlayStatus == nil)
  }

  @Test func microphoneFallbackUsesTopLevelAppToast() {
    let toast = FeedbackToastPresenter()
    var overlayStatus: OverlayStatus?
    let presenter = RecordingFeedbackPresenter(toast: toast) { status in
      overlayStatus = status
    }

    presenter.present(RecordingFeedback(.microphoneFallbackToSystemDefault))

    #expect(toast.presented.count == 1)
    #expect(toast.presented[0].message.type == .warning)
    #expect(toast.presented[0].message.title == "Mic Unavailable")
    #expect(toast.presented[0].anchor == .topCenter)
    #expect(overlayStatus == nil)
  }

  @Test func previewFailureUsesOverlayStatus() {
    let toast = FeedbackToastPresenter()
    var overlayStatus: OverlayStatus?
    let presenter = RecordingFeedbackPresenter(toast: toast) { status in
      overlayStatus = status
    }

    presenter.present(RecordingFeedback(.livePreviewUnavailable))

    #expect(toast.presented.isEmpty)
    #expect(overlayStatus?.kind == .warning)
    #expect(overlayStatus?.title == "Live Preview Unavailable")
  }

  @Test func clearOverlayStatusClearsPresentedOverlay() {
    let toast = FeedbackToastPresenter()
    var overlayStatus: OverlayStatus?
    let presenter = RecordingFeedbackPresenter(toast: toast) { status in
      overlayStatus = status
    }

    presenter.present(RecordingFeedback(.recordingCanceled))
    presenter.clearOverlayStatus()

    #expect(toast.presented.isEmpty)
    #expect(overlayStatus == nil)
  }
}

@MainActor
private final class FeedbackToastPresenter: ToastPresenting, @unchecked Sendable {
  struct Presented {
    let message: ToastMessage
    let anchor: ToastWindowController.Anchor
  }

  private(set) var presented: [Presented] = []

  func show(_ toast: ToastMessage, anchor: ToastWindowController.Anchor) {
    presented.append(Presented(message: toast, anchor: anchor))
  }

  func showError(title: String, message: String?) {
    presented.append(
      Presented(
        message: ToastMessage(type: .error, title: title, message: message),
        anchor: .topCenter
      ))
  }
}
