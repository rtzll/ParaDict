import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
protocol HotkeyManagerDelegate: AnyObject {
  nonisolated func hotkeyDidToggleRecording()
  nonisolated func hotkeyDidCancelRecording()
}

/// Thread-safe box for the recording-active flag. Accessed from both the
/// @MainActor (writes) and the event-tap thread (reads), so mutations are
/// protected by an NSLock.
private final class RecordingActiveState: @unchecked Sendable {
  private let lock = NSLock()
  private var isRecording = false

  func start() {
    lock.lock()
    isRecording = true
    lock.unlock()
  }

  func end() {
    lock.lock()
    isRecording = false
    lock.unlock()
  }

  var active: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isRecording
  }
}

@MainActor
final class HotkeyManager {
  weak var delegate: HotkeyManagerDelegate?

  private let shortcutMonitor = CustomShortcutMonitor.shared
  private let recordingState = RecordingActiveState()

  func start() {
    setupToggleRecording()
    setupCancelRecording()
    shortcutMonitor.start()
  }

  func stop() {
    shortcutMonitor.stop()
  }

  func reloadShortcuts() {
    shortcutMonitor.reloadShortcuts()
  }

  func recordingDidStart() {
    recordingState.start()
  }

  func recordingDidEnd() {
    recordingState.end()
  }

  private func setupToggleRecording() {
    shortcutMonitor.onKeyDown(for: .toggleRecording) { [weak self] in
      self?.delegate?.hotkeyDidToggleRecording()
    }
  }

  private func setupCancelRecording() {
    shortcutMonitor.setEnabledCheck(for: .cancelRecording) { [recordingState] in
      recordingState.active
    }
    shortcutMonitor.onKeyUp(for: .cancelRecording) { [weak self] in
      self?.delegate?.hotkeyDidCancelRecording()
    }
  }
}
