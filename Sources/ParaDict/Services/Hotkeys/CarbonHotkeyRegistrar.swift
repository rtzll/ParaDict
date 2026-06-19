import Carbon.HIToolbox
import Foundation
import os.log

private let carbonHotkeyLog = Logger(subsystem: Logger.subsystem, category: "CarbonHotkey")

final class CarbonHotkeyRegistrar: @unchecked Sendable {
  typealias Handler = @Sendable @MainActor () -> Void

  private static let signature: OSType = 0x5044_4354  // "PDCT"

  private let id: UInt32
  private let lock = NSLock()
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var handler: Handler?

  init(id: UInt32) {
    self.id = id
  }

  deinit {
    unregister()
  }

  func register(shortcut: CustomShortcut, handler: @escaping Handler) -> Bool {
    unregister()

    guard shortcut.canRegisterAsCarbonHotkey else {
      carbonHotkeyLog.info("Skipping Carbon registration for \(shortcut.compactDisplayString)")
      return false
    }

    lock.lock()
    self.handler = handler
    lock.unlock()

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      Self.handleEvent,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandlerRef
    )

    guard handlerStatus == noErr else {
      carbonHotkeyLog.error("Failed to install Carbon hotkey handler: \(handlerStatus)")
      clearHandler()
      return false
    }

    let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
    let registerStatus = RegisterEventHotKey(
      UInt32(shortcut.keyCode),
      shortcut.carbonModifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    guard registerStatus == noErr else {
      carbonHotkeyLog.error(
        "Failed to register Carbon hotkey \(shortcut.compactDisplayString): \(registerStatus)"
      )
      unregister()
      return false
    }

    carbonHotkeyLog.info("Registered Carbon hotkey \(shortcut.compactDisplayString)")
    return true
  }

  func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }

    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
      self.eventHandlerRef = nil
    }

    clearHandler()
  }

  private func clearHandler() {
    lock.lock()
    handler = nil
    lock.unlock()
  }

  private func currentHandler() -> Handler? {
    lock.lock()
    defer { lock.unlock() }
    return handler
  }

  private func handles(event: EventRef?) -> Bool {
    guard let event else { return false }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &hotKeyID
    )
    guard status == noErr else { return false }
    return hotKeyID.signature == Self.signature && hotKeyID.id == id
  }

  private static let handleEvent: EventHandlerUPP = { _, event, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }

    let registrar = Unmanaged<CarbonHotkeyRegistrar>
      .fromOpaque(userData)
      .takeUnretainedValue()

    guard registrar.handles(event: event), let handler = registrar.currentHandler() else {
      return OSStatus(eventNotHandledErr)
    }

    Task { @MainActor in
      handler()
    }
    return noErr
  }
}

extension CustomShortcut {
  var canRegisterAsCarbonHotkey: Bool {
    !fn && !isFnOnly && (command || option || control || shift)
  }

  var carbonModifiers: UInt32 {
    var modifiers: UInt32 = 0
    if command { modifiers |= UInt32(cmdKey) }
    if option { modifiers |= UInt32(optionKey) }
    if control { modifiers |= UInt32(controlKey) }
    if shift { modifiers |= UInt32(shiftKey) }
    return modifiers
  }
}
