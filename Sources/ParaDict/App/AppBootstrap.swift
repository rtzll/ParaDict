import os.log

private let bootstrapLog = Logger(subsystem: Logger.subsystem, category: "AppBootstrap")

@MainActor
final class AppBootstrap {
  private let recordingController: RecordingController
  private let recordingStore: RecordingStore
  private let analyticsStore: AnalyticsStore
  private let permissions: PermissionsManager
  private let hotkeyManager: HotkeyManager

  init(
    recordingController: RecordingController,
    recordingStore: RecordingStore,
    analyticsStore: AnalyticsStore,
    permissions: PermissionsManager,
    hotkeyManager: HotkeyManager
  ) {
    self.recordingController = recordingController
    self.recordingStore = recordingStore
    self.analyticsStore = analyticsStore
    self.permissions = permissions
    self.hotkeyManager = hotkeyManager
  }

  func start() async {
    try? await recordingStore.loadAll()
    await recordingStore.performRetention()

    let analyticsExisted = await analyticsStore.load()
    if !analyticsExisted {
      await analyticsStore.seedFromRecordings(recordingStore.recordings)
    }

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
