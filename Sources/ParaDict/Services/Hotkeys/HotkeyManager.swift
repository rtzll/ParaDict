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

private final class ToggleHotkeyRoutingState: @unchecked Sendable {
  private let lock = NSLock()
  private var handledByCarbon = false

  func setHandledByCarbon(_ enabled: Bool) {
    lock.lock()
    handledByCarbon = enabled
    lock.unlock()
  }

  var shouldUseEventTapFallback: Bool {
    lock.lock()
    defer { lock.unlock() }
    return !handledByCarbon
  }
}

@MainActor
final class HotkeyManager {
  weak var delegate: HotkeyManagerDelegate?

  private let shortcutMonitor = CustomShortcutMonitor.shared
  private let carbonToggleHotkey = CarbonHotkeyRegistrar(id: 1)
  private let recordingState = RecordingActiveState()
  private let toggleRoutingState = ToggleHotkeyRoutingState()

  func start() {
    setupToggleRecording()
    setupCancelRecording()
    registerCarbonToggleShortcut()
    shortcutMonitor.start()
  }

  func stop() {
    carbonToggleHotkey.unregister()
    toggleRoutingState.setHandledByCarbon(false)
    shortcutMonitor.stop()
  }

  func reloadShortcuts() {
    shortcutMonitor.reloadShortcuts()
    registerCarbonToggleShortcut()
  }

  func recordingDidStart() {
    recordingState.start()
  }

  func recordingDidEnd() {
    recordingState.end()
  }

  private func setupToggleRecording() {
    shortcutMonitor.setEnabledCheck(for: .toggleRecording) { [toggleRoutingState] in
      toggleRoutingState.shouldUseEventTapFallback
    }
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

  private func registerCarbonToggleShortcut() {
    guard let shortcut = CustomShortcutStorage.get(.toggleRecording) else {
      carbonToggleHotkey.unregister()
      toggleRoutingState.setHandledByCarbon(false)
      return
    }

    let registered = carbonToggleHotkey.register(shortcut: shortcut) { [weak self] in
      self?.delegate?.hotkeyDidToggleRecording()
    }
    toggleRoutingState.setHandledByCarbon(registered)
  }
}
