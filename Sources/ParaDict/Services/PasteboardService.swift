import AppKit
import Carbon.HIToolbox
import Foundation
import os.log

typealias PasteboardSnapshot = [[String: Data]]

protocol PasteboardAccess: AnyObject, Sendable {
  var changeCount: Int { get }
  func snapshotContents() -> PasteboardSnapshot?
  @discardableResult func setString(_ text: String) -> Bool
  func restoreContents(_ snapshot: PasteboardSnapshot)
}

protocol PasteboardScheduler: Sendable {
  func schedule(after delay: TimeInterval, _ operation: @escaping @Sendable () -> Void)
}

/// Wraps `NSPasteboard`, which is not declared `Sendable` but is documented
/// as safe to use from multiple threads. All mutations are serialized through
/// the single shared pasteboard instance.
private final class SystemPasteboardAccess: PasteboardAccess, @unchecked Sendable {
  private let pasteboard = NSPasteboard.general

  var changeCount: Int { pasteboard.changeCount }

  func snapshotContents() -> PasteboardSnapshot? {
    guard let items = pasteboard.pasteboardItems else {
      return nil
    }

    var savedItems: PasteboardSnapshot = []
    for item in items {
      var itemData: [String: Data] = [:]
      for type in item.types {
        if let data = item.data(forType: type) {
          itemData[type.rawValue] = data
        }
      }
      if !itemData.isEmpty {
        savedItems.append(itemData)
      }
    }

    return savedItems.isEmpty ? nil : savedItems
  }

  @discardableResult
  func setString(_ text: String) -> Bool {
    pasteboard.clearContents()
    return pasteboard.setString(text, forType: .string)
  }

  func restoreContents(_ snapshot: PasteboardSnapshot) {
    pasteboard.clearContents()

    let items = snapshot.map { itemData in
      let item = NSPasteboardItem()
      for (rawType, data) in itemData {
        item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: rawType))
      }
      return item
    }

    pasteboard.writeObjects(items)
  }
}

private struct DispatchPasteboardScheduler: PasteboardScheduler {
  func schedule(after delay: TimeInterval, _ operation: @escaping @Sendable () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: operation)
  }
}

final class PasteboardService: Sendable {
  private let logger = Logger(subsystem: Logger.subsystem, category: "PasteboardService")
  private let pasteboard: PasteboardAccess
  private let scheduler: PasteboardScheduler
  private let pasteAction: (@Sendable () -> Void)?

  init(
    pasteboard: PasteboardAccess = SystemPasteboardAccess(),
    scheduler: PasteboardScheduler = DispatchPasteboardScheduler(),
    pasteAction: (@Sendable () -> Void)? = nil
  ) {
    self.pasteboard = pasteboard
    self.scheduler = scheduler
    self.pasteAction = pasteAction
  }

  @discardableResult
  func copy(_ text: String) -> Bool {
    pasteboard.setString(text)
  }

  func copyAndPaste(_ text: String) {
    logger.info("copyAndPaste called with \(text.count) characters")

    let savedContents = pasteboard.snapshotContents()
    let changeCountBefore = pasteboard.changeCount

    guard copy(text) else {
      logger.error("Failed to copy text to clipboard")
      return
    }

    let changeCountAfter = pasteboard.changeCount

    if changeCountAfter > changeCountBefore {
      logger.info("Copy succeeded, simulating paste...")

      // 50ms: let the frontmost app's run loop process the clipboard change before pasting
      scheduler.schedule(after: 0.05) { [weak self] in
        guard let self else { return }
        self.performPaste()

        // 300ms: wait for the target app to read the pasted content before restoring
        self.scheduler.schedule(after: 0.3) { [weak self] in
          self?.restorePasteboardContents(savedContents, expectedChangeCount: changeCountAfter)
        }
      }
    } else {
      logger.error("Copy did not change clipboard")
    }
  }

  private func restorePasteboardContents(_ saved: PasteboardSnapshot?, expectedChangeCount: Int) {
    guard let saved, !saved.isEmpty else {
      return
    }

    guard pasteboard.changeCount == expectedChangeCount else {
      logger.info("Clipboard changed after paste, skipping restore")
      return
    }

    pasteboard.restoreContents(saved)
    logger.info("Clipboard restored")
  }

  private func performPaste() {
    if let pasteAction {
      pasteAction()
    } else {
      simulatePaste()
    }
  }

  // MARK: - Keystroke Simulation

  private func simulatePaste() {
    logger.info("Simulating Cmd+V paste...")

    let source = CGEventSource(stateID: .hidSystemState)

    guard
      let keyDown = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
    else {
      logger.error("Failed to create keyDown event - check Accessibility permissions")
      return
    }
    keyDown.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)

    // 10ms gap so the target app sees distinct keyDown/keyUp events
    usleep(10000)

    guard
      let keyUp = CGEvent(
        keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
    else {
      logger.error("Failed to create keyUp event")
      return
    }
    keyUp.flags = .maskCommand
    keyUp.post(tap: .cghidEventTap)

    logger.info("Paste keystroke sent")
  }
}
