import AppKit
import Testing

@testable import ParaDict

struct PasteboardServiceTests {
  @Test func restoresSavedClipboardWhenNoExternalClipboardChangeOccurs() {
    let pasteboard = FakePasteboard()
    pasteboard.seedString("old clipboard")
    let scheduler = TestPasteboardScheduler()
    let service = PasteboardService(
      pasteboard: pasteboard,
      scheduler: scheduler,
      pasteAction: {}
    )

    service.copyAndPaste("dictated text")

    #expect(scheduler.pendingCount == 1)
    scheduler.runNext()
    #expect(pasteboard.currentString == "dictated text")
    #expect(scheduler.pendingCount == 1)

    scheduler.runNext()

    #expect(pasteboard.currentString == "old clipboard")
  }

  @Test func skipsRestoreWhenClipboardChangesAfterPaste() {
    let pasteboard = FakePasteboard()
    pasteboard.seedString("old clipboard")
    let scheduler = TestPasteboardScheduler()
    let service = PasteboardService(
      pasteboard: pasteboard,
      scheduler: scheduler,
      pasteAction: {}
    )

    service.copyAndPaste("dictated text")

    scheduler.runNext()
    pasteboard.simulateExternalCopy("external change")
    scheduler.runNext()

    #expect(pasteboard.currentString == "external change")
  }
}

private final class FakePasteboard: PasteboardAccess, @unchecked Sendable {
  private(set) var changeCount: Int = 0
  private var snapshot: PasteboardSnapshot?

  var currentString: String? {
    guard
      let rawValue = snapshot?.first?[NSPasteboard.PasteboardType.string.rawValue],
      let string = String(data: rawValue, encoding: .utf8)
    else {
      return nil
    }
    return string
  }

  func seedString(_ string: String) {
    snapshot = Self.snapshot(for: string)
    changeCount += 1
  }

  func simulateExternalCopy(_ string: String) {
    snapshot = Self.snapshot(for: string)
    changeCount += 1
  }

  func snapshotContents() -> PasteboardSnapshot? {
    snapshot
  }

  @discardableResult
  func setString(_ text: String) -> Bool {
    snapshot = Self.snapshot(for: text)
    changeCount += 1
    return true
  }

  func restoreContents(_ snapshot: PasteboardSnapshot) {
    self.snapshot = snapshot
    changeCount += 1
  }

  private static func snapshot(for string: String) -> PasteboardSnapshot {
    [[NSPasteboard.PasteboardType.string.rawValue: Data(string.utf8)]]
  }
}

private final class TestPasteboardScheduler: PasteboardScheduler, @unchecked Sendable {
  private var operations: [@Sendable () -> Void] = []

  var pendingCount: Int {
    operations.count
  }

  func schedule(after delay: TimeInterval, _ operation: @escaping @Sendable () -> Void) {
    operations.append(operation)
  }

  func runNext() {
    let operation = operations.removeFirst()
    operation()
  }
}
