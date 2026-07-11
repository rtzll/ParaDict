import AppKit

@MainActor
final class AppContainer {
  let recordingController: RecordingController
  let menuBarViewModel: MenuBarViewModel
  let overlayViewModel: OverlayViewModel
  let hotkeyRouter: HotkeyRouter
  let bootstrap: AppBootstrap

  init(toast: ToastPresenting = ToastWindowController.shared) {
    let recorder = AudioRecorder()
    let deviceManager = AudioDeviceManager()
    let mediaPlayback = MediaPlaybackController()
    let recordingHistory = RecordingHistory()
    let permissions = PermissionsManager()
    let pasteboard = PasteboardService()

    let recordingController = RecordingController(
      recorder: recorder,
      deviceManager: deviceManager,
      mediaPlayback: mediaPlayback,
      toast: toast,
      transcriptionProvider: ParakeetProvider(),
      recordingHistory: recordingHistory,
      pasteboardWriter: pasteboard
    )

    let hotkeyRouter = HotkeyRouter()
    hotkeyRouter.onIntent = { [weak recordingController] intent in
      switch intent {
      case .toggleRecording:
        recordingController?.toggleRecording()
      case .cancelRecording:
        recordingController?.handleCancelRecordingShortcut()
      }
    }

    self.recordingController = recordingController
    menuBarViewModel = MenuBarViewModel(
      recordingController: recordingController,
      recordingHistory: recordingHistory,
      permissions: permissions,
      pasteboard: pasteboard,
      hotkeyRouter: hotkeyRouter
    )
    overlayViewModel = OverlayViewModel(recordingController: recordingController)
    self.hotkeyRouter = hotkeyRouter
    bootstrap = AppBootstrap(
      recordingController: recordingController,
      recordingHistory: recordingHistory,
      permissions: permissions,
      hotkeyRouter: hotkeyRouter
    )
  }
}
