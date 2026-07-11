import os.log

private let bootstrapLog = Logger(subsystem: Logger.subsystem, category: "AppBootstrap")

@MainActor
final class AppBootstrap {
  private let recordingController: RecordingController
  private let recordingHistory: RecordingHistory
  private let permissions: PermissionsManager
  private let hotkeyManager: HotkeyManager

  init(
    recordingController: RecordingController,
    recordingHistory: RecordingHistory,
    permissions: PermissionsManager,
    hotkeyManager: HotkeyManager
  ) {
    self.recordingController = recordingController
    self.recordingHistory = recordingHistory
    self.permissions = permissions
    self.hotkeyManager = hotkeyManager
  }

  func start() async {
    do {
      try await recordingHistory.loadAll()
    } catch {
      bootstrapLog.error(
        "Failed to load recordings; continuing with empty in-memory history: \(error.localizedDescription)"
      )
    }
    await recordingHistory.performRetention()

    permissions.refresh()

    if !permissions.microphoneGranted {
      await permissions.requestMicrophone()
    }

    recordingController.preloadModel()
    wireHotkeyLifecycle()

    if permissions.accessibilityGranted {
      bootstrapLog.info("Starting hotkey manager (accessibility already granted)")
      hotkeyManager.start()
    } else {
      permissions.openAccessibilitySettings()
      permissions.startPolling()
    }
  }

  private func wireHotkeyLifecycle() {
    recordingController.onRecordingStarted = { [weak hotkeyManager] in
      hotkeyManager?.recordingDidStart()
    }
    recordingController.onRecordingEnded = { [weak hotkeyManager] in
      hotkeyManager?.recordingDidEnd()
    }

    permissions.onAllGranted = { [weak hotkeyManager] in
      bootstrapLog.info("All permissions granted — restarting hotkey manager")
      hotkeyManager?.stop()
      hotkeyManager?.start()
    }
  }
}
