import Testing

@testable import ParaDict

@MainActor
struct OverlayStatusPresenterTests {
  @Test func clearsStatusAfterDismissalDelay() async {
    var statusChanges: [OverlayStatus?] = []
    let presenter = OverlayStatusPresenter { status in
      statusChanges.append(status)
    }

    presenter.show(
      OverlayStatus(kind: .warning, title: "Warning", message: "details"), duration: 0.01)

    #expect(statusChanges.count == 1)
    #expect(statusChanges[0]?.title == "Warning")

    await presenter.awaitPendingDismissalForTesting()

    #expect(statusChanges.count == 2)
    #expect(statusChanges[1] == nil)
  }

  @Test func replacingStatusCancelsPreviousDismissal() async {
    var currentStatus: OverlayStatus?
    let presenter = OverlayStatusPresenter { status in
      currentStatus = status
    }

    presenter.show(OverlayStatus(kind: .info, title: "First", message: nil), duration: 0.05)
    presenter.show(OverlayStatus(kind: .error, title: "Second", message: nil), duration: 0.01)

    #expect(currentStatus?.title == "Second")

    await presenter.awaitPendingDismissalForTesting()

    #expect(currentStatus == nil)
  }
}
