import os.log

private let bootstrapLog = Logger(subsystem: Logger.subsystem, category: "AppBootstrap")

@MainActor
final class AppBootstrap {
  private let recordingController: RecordingController
  private let recordingHistory: RecordingHistory
  private let permissions: PermissionsManager
  private let hotkeyRouter: HotkeyRouter

  init(
    recordingController: RecordingController,
    recordingHistory: RecordingHistory,
    permissions: PermissionsManager,
    hotkeyRouter: HotkeyRouter
  ) {
    self.recordingController = recordingController
    self.recordingHistory = recordingHistory
    self.permissions = permissions
    self.hotkeyRouter = hotkeyRouter
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
      hotkeyRouter.start()
    } else {
      permissions.openAccessibilitySettings()
      permissions.startPolling()
    }
  }

  private func wireHotkeyLifecycle() {
    recordingController.onRecordingStarted = { [weak hotkeyRouter] in
      hotkeyRouter?.recordingDidStart()
    }
    recordingController.onRecordingEnded = { [weak hotkeyRouter] in
      hotkeyRouter?.recordingDidEnd()
    }

    permissions.onAllGranted = { [weak hotkeyRouter] in
      bootstrapLog.info("All permissions granted — restarting hotkey manager")
      hotkeyRouter?.stop()
      hotkeyRouter?.start()
    }
  }
}
