import Testing

@testable import ParaDict

@MainActor
@Suite(.serialized)
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

  @Test func fallsBackToEventTapWhenCarbonRegistrationFails() {
    let monitor = TestHotkeyMonitor()
    let registrar = TestToggleHotkeyRegistrar(registrationSucceeds: false)
    let router = HotkeyRouter(monitor: monitor, toggleRegistrar: registrar)
    var intents: [HotkeyIntent] = []
    router.onIntent = { intents.append($0) }

    router.start()

    #expect(monitor.isEnabled(.toggleRecording))
    monitor.triggerKeyDown(.toggleRecording)
    #expect(intents == [.toggleRecording])
  }

  @Test func updatingToggleShortcutReloadsAndReregistersAdapters() {
    let original = CustomShortcutStorage.get(.toggleRecording)
    let monitor = TestHotkeyMonitor()
    let registrar = TestToggleHotkeyRegistrar(registrationSucceeds: true)
    let router = HotkeyRouter(monitor: monitor, toggleRegistrar: registrar)
    let replacement = CustomShortcut(keyCode: 40, command: true)

    router.updateShortcut(replacement, for: .toggleRecording)

    #expect(monitor.reloadCount == 1)
    #expect(registrar.registerCount == 1)
    #expect(CustomShortcutStorage.get(.toggleRecording) == replacement)

    router.updateShortcut(original, for: .toggleRecording)
  }
}

@MainActor
private final class TestHotkeyMonitor: HotkeyMonitoring {
  private var keyDownHandlers: [CustomShortcutName: @Sendable @MainActor () -> Void] = [:]
  private var keyUpHandlers: [CustomShortcutName: @Sendable @MainActor () -> Void] = [:]
  private var enabledChecks: [CustomShortcutName: @Sendable () -> Bool] = [:]
  private(set) var reloadCount = 0

  func start() {}
  func stop() {}
  func reloadShortcuts() { reloadCount += 1 }

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

  func triggerKeyDown(_ name: CustomShortcutName) {
    keyDownHandlers[name]?()
  }
}

@MainActor
private final class TestToggleHotkeyRegistrar: ToggleHotkeyRegistering {
  private let registrationSucceeds: Bool
  private var handler: (@Sendable @MainActor () -> Void)?
  private(set) var registerCount = 0

  init(registrationSucceeds: Bool) {
    self.registrationSucceeds = registrationSucceeds
  }

  func register(
    shortcut: CustomShortcut,
    handler: @escaping @Sendable @MainActor () -> Void
  ) -> Bool {
    registerCount += 1
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
