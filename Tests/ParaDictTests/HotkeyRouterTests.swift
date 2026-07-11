import Testing

@testable import ParaDict

@MainActor
struct HotkeyRouterTests {
  @Test func routesCarbonToggleAndRecordingGatedCancellation() {
    let monitor = TestHotkeyMonitor()
    let registrar = TestToggleHotkeyRegistrar(registrationSucceeds: true)
    let router = HotkeyRouter(monitor: monitor, toggleRegistrar: registrar)
    var intents: [HotkeyIntent] = []
    router.onIntent = { intents.append($0) }

    router.start()

    #expect(monitor.isEnabled(.toggleRecording) == false)
    registrar.trigger()
    #expect(intents == [.toggleRecording])

    #expect(monitor.isEnabled(.cancelRecording) == false)
    router.recordingDidStart()
    #expect(monitor.isEnabled(.cancelRecording))
    monitor.triggerKeyUp(.cancelRecording)
    #expect(intents == [.toggleRecording, .cancelRecording])
  }
}

@MainActor
private final class TestHotkeyMonitor: HotkeyMonitoring {
  private var keyDownHandlers: [CustomShortcutName: @Sendable @MainActor () -> Void] = [:]
  private var keyUpHandlers: [CustomShortcutName: @Sendable @MainActor () -> Void] = [:]
  private var enabledChecks: [CustomShortcutName: @Sendable () -> Bool] = [:]

  func start() {}
  func stop() {}
  func reloadShortcuts() {}

  func onKeyDown(
    for name: CustomShortcutName,
    handler: @escaping @Sendable @MainActor () -> Void
  ) {
    keyDownHandlers[name] = handler
  }

  func onKeyUp(
    for name: CustomShortcutName,
    handler: @escaping @Sendable @MainActor () -> Void
  ) {
    keyUpHandlers[name] = handler
  }

  func setEnabledCheck(
    for name: CustomShortcutName,
    check: @escaping @Sendable () -> Bool
  ) {
    enabledChecks[name] = check
  }

  func isEnabled(_ name: CustomShortcutName) -> Bool {
    enabledChecks[name]?() ?? true
  }

  func triggerKeyUp(_ name: CustomShortcutName) {
    keyUpHandlers[name]?()
  }
}

@MainActor
private final class TestToggleHotkeyRegistrar: ToggleHotkeyRegistering {
  private let registrationSucceeds: Bool
  private var handler: (@Sendable @MainActor () -> Void)?

  init(registrationSucceeds: Bool) {
    self.registrationSucceeds = registrationSucceeds
  }

  func register(
    shortcut: CustomShortcut,
    handler: @escaping @Sendable @MainActor () -> Void
  ) -> Bool {
    self.handler = handler
    return registrationSucceeds
  }

  func unregister() {
    handler = nil
  }

  func trigger() {
    handler?()
  }
}
