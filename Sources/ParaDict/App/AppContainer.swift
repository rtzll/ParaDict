import AppKit

@MainActor
final class AppContainer {
  let recordingController: RecordingController
  let menuBarViewModel: MenuBarViewModel
  let overlayViewModel: OverlayViewModel
  let hotkeyManager: HotkeyManager
  let hotkeyDelegate: HotkeyDelegateImpl
  let bootstrap: AppBootstrap

  init(toast: ToastPresenting = ToastWindowController.shared) {
    let recorder = AudioRecorder()
    let deviceManager = AudioDeviceManager()
    let mediaPlayback = MediaPlaybackController()
    let recordingStore = RecordingStore()
    let analyticsStore = AnalyticsStore()
    let permissions = PermissionsManager()
    let pasteboard = PasteboardService()
    let sessionRuntime = RecordingSessionRuntime()

    let recordingController = RecordingController(
      recorder: recorder,
      deviceManager: deviceManager,
      mediaPlayback: mediaPlayback,
      sessionRuntime: sessionRuntime,
      toast: toast,
      transcriptionProvider: ParakeetProvider(),
      recordingPersistence: recordingStore,
      analyticsRecording: analyticsStore,
      pasteboardWriter: pasteboard
    )

    let hotkeyManager = HotkeyManager()
    let hotkeyDelegate = HotkeyDelegateImpl(recordingController: recordingController)
    hotkeyManager.delegate = hotkeyDelegate

    self.recordingController = recordingController
    menuBarViewModel = MenuBarViewModel(
      recordingController: recordingController,
      recordingStore: recordingStore,
      analyticsStore: analyticsStore,
      permissions: permissions,
      pasteboard: pasteboard
    )
    overlayViewModel = OverlayViewModel(recordingController: recordingController)
    self.hotkeyManager = hotkeyManager
    self.hotkeyDelegate = hotkeyDelegate
    bootstrap = AppBootstrap(
      recordingController: recordingController,
      recordingStore: recordingStore,
      analyticsStore: analyticsStore,
      permissions: permissions,
      hotkeyManager: hotkeyManager
    )
  }
}
