import AppKit
import Carbon.HIToolbox
import Foundation

enum HotkeyIntent: Equatable, Sendable {
  case toggleRecording
  case cancelRecording
}

@MainActor
protocol HotkeyMonitoring: AnyObject {
  func start()
  func stop()
  func reloadShortcuts()
  func onKeyDown(
    for name: CustomShortcutName,
    handler: @escaping @Sendable @MainActor () -> Void
  )
  func onKeyUp(
    for name: CustomShortcutName,
    handler: @escaping @Sendable @MainActor () -> Void
  )
  func setEnabledCheck(
    for name: CustomShortcutName,
    check: @escaping @Sendable () -> Bool
  )
}

@MainActor
protocol ToggleHotkeyRegistering: AnyObject {
  func register(
    shortcut: CustomShortcut,
    handler: @escaping @Sendable @MainActor () -> Void
  ) -> Bool
  func unregister()
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
final class HotkeyRouter {
  var onIntent: (@MainActor (HotkeyIntent) -> Void)?

  private let shortcutMonitor: HotkeyMonitoring
  private let carbonToggleHotkey: ToggleHotkeyRegistering
  private let recordingState = RecordingActiveState()
  private let toggleRoutingState = ToggleHotkeyRoutingState()

  init(
    monitor: HotkeyMonitoring = CustomShortcutMonitor.shared,
    toggleRegistrar: ToggleHotkeyRegistering = CarbonHotkeyRegistrar(id: 1)
  ) {
    self.shortcutMonitor = monitor
    self.carbonToggleHotkey = toggleRegistrar
  }

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

  func updateShortcut(_ shortcut: CustomShortcut?, for name: CustomShortcutName) {
    CustomShortcutStorage.set(shortcut, for: name)
    shortcutMonitor.reloadShortcuts()
    if name == .toggleRecording {
      registerCarbonToggleShortcut()
    }
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
      self?.onIntent?(.toggleRecording)
    }
  }

  private func setupCancelRecording() {
    shortcutMonitor.setEnabledCheck(for: .cancelRecording) { [recordingState] in
      recordingState.active
    }
    shortcutMonitor.onKeyUp(for: .cancelRecording) { [weak self] in
      self?.onIntent?(.cancelRecording)
    }
  }

  private func registerCarbonToggleShortcut() {
    guard let shortcut = CustomShortcutStorage.get(.toggleRecording) else {
      carbonToggleHotkey.unregister()
      toggleRoutingState.setHandledByCarbon(false)
      return
    }

    let registered = carbonToggleHotkey.register(shortcut: shortcut) { [weak self] in
      self?.onIntent?(.toggleRecording)
    }
    toggleRoutingState.setHandledByCarbon(registered)
  }
}

extension CustomShortcutMonitor: HotkeyMonitoring {}
extension CarbonHotkeyRegistrar: ToggleHotkeyRegistering {}
