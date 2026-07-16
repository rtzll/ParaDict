import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingFeedbackPresenterTests {
  @Test func modelReadinessBlockUsesTransientCursorError() {
    let toast = TestToastPresenter()
    var overlayStatus: OverlayStatus?
    let presenter = RecordingFeedbackPresenter(toast: toast) { status in
      overlayStatus = status
    }

    presenter.present(
      RecordingFeedback(
        .modelReadinessBlocked(
          ModelReadinessFailure(title: "Model Loading", message: "Please wait"))))

    #expect(toast.messages.count == 1)
    #expect(toast.messages[0].toast.type == .error)
    #expect(toast.messages[0].toast.title == "Model Loading")
    #expect(toast.messages[0].anchor == .cursor())
    #expect(overlayStatus == nil)
  }

  @Test func microphoneFallbackUsesTopLevelAppToast() {
    let toast = TestToastPresenter()
    var overlayStatus: OverlayStatus?
    let presenter = RecordingFeedbackPresenter(toast: toast) { status in
      overlayStatus = status
    }

    presenter.present(RecordingFeedback(.microphoneFallbackToSystemDefault))

    #expect(toast.messages.count == 1)
    #expect(toast.messages[0].toast.type == .warning)
    #expect(toast.messages[0].toast.title == "Mic Unavailable")
    #expect(toast.messages[0].anchor == .topCenter)
    #expect(overlayStatus == nil)
  }

  @Test func previewFailureUsesOverlayStatus() {
    let toast = TestToastPresenter()
    var overlayStatus: OverlayStatus?
    let presenter = RecordingFeedbackPresenter(toast: toast) { status in
      overlayStatus = status
    }

    presenter.present(RecordingFeedback(.livePreviewUnavailable))

    #expect(toast.messages.isEmpty)
    #expect(overlayStatus?.kind == .warning)
    #expect(overlayStatus?.title == "Live Preview Unavailable")
  }

  @Test func successfulTranscriptionUsesCompletionOverlayStatus() {
    let toast = TestToastPresenter()
    var overlayStatus: OverlayStatus?
    let presenter = RecordingFeedbackPresenter(toast: toast) { status in
      overlayStatus = status
    }

    presenter.present(RecordingFeedback(.transcriptionSucceeded))

    #expect(toast.messages.isEmpty)
    #expect(overlayStatus?.kind == .success)
    #expect(overlayStatus?.title == "Inserted")
  }

  @Test func clearOverlayStatusClearsPresentedOverlay() {
    let toast = TestToastPresenter()
    var overlayStatus: OverlayStatus?
    let presenter = RecordingFeedbackPresenter(toast: toast) { status in
      overlayStatus = status
    }

    presenter.present(RecordingFeedback(.recordingCanceled))
    presenter.clearOverlayStatus()

    #expect(toast.messages.isEmpty)
    #expect(overlayStatus == nil)
  }
}
