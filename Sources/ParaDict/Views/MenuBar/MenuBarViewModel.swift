import AppKit
import Foundation
import Observation

struct MenuBarSnapshot: Sendable {
  let recordingState: RecordingState
  let currentDuration: TimeInterval
  let modelReadiness: ModelReadinessMenuPresentation
  let allPermissionsGranted: Bool
  let accessibilityGranted: Bool
  let microphoneGranted: Bool
  let inputMode: MicInputMode
  let selectedDeviceUID: String?
  let systemDefaultDeviceName: String
  let effectiveDeviceName: String
  let isSelectedDeviceAvailable: Bool
  let availableDevices: [AudioInputDevice]
  let recentHistoryItems: [Recording]
  let statistics: RecordingStatistics
  let toggleRecordingShortcut: CustomShortcut?
}

@Observable
@MainActor
final class MenuBarViewModel: Sendable {
  private let recordingController: RecordingController
  private let recordingHistory: RecordingHistory
  private let permissions: PermissionsManager
  private let pasteboard: PasteboardService
  private let hotkeyRouter: HotkeyRouter
  private let openRecordingsFolderAction: @MainActor () -> Void
  private let quitApplicationAction: @MainActor () -> Void

  init(
    recordingController: RecordingController,
    recordingHistory: RecordingHistory,
    permissions: PermissionsManager,
    pasteboard: PasteboardService,
    hotkeyRouter: HotkeyRouter,
    openRecordingsFolderAction: @escaping @MainActor () -> Void = {
      NSWorkspace.shared.selectFile(
        nil,
        inFileViewerRootedAtPath: Recording.baseDirectory.deletingLastPathComponent().path
      )
    },
    quitApplicationAction: @escaping @MainActor () -> Void = {
      NSApplication.shared.terminate(nil)
    }
  ) {
    self.recordingController = recordingController
    self.recordingHistory = recordingHistory
    self.permissions = permissions
    self.pasteboard = pasteboard
    self.hotkeyRouter = hotkeyRouter
    self.openRecordingsFolderAction = openRecordingsFolderAction
    self.quitApplicationAction = quitApplicationAction
  }

  var snapshot: MenuBarSnapshot {
    let recording = recordingController.presentationSnapshot
    return MenuBarSnapshot(
      recordingState: recording.state,
      currentDuration: recording.duration,
      modelReadiness: recording.modelReadiness,
      allPermissionsGranted: permissions.allGranted,
      accessibilityGranted: permissions.accessibilityGranted,
      microphoneGranted: permissions.microphoneGranted,
      inputMode: recording.audioDevice.inputMode,
      selectedDeviceUID: recording.audioDevice.selectedDeviceUID,
      systemDefaultDeviceName: recording.audioDevice.systemDefaultDeviceName,
      effectiveDeviceName: recording.audioDevice.effectiveDeviceName,
      isSelectedDeviceAvailable: recording.audioDevice.isSelectedDeviceAvailable,
      availableDevices: recording.audioDevice.availableDevices,
      recentHistoryItems: recordingHistory.recentHistoryItems,
      statistics: recordingHistory.statistics,
      toggleRecordingShortcut: CustomShortcutStorage.get(.toggleRecording)
    )
  }

  func selectDevice(_ device: AudioInputDevice) {
    recordingController.selectDevice(device)
  }

  func selectSystemDefaultMicrophone() {
    recordingController.selectSystemDefaultMicrophone()
  }

  func updateToggleRecordingShortcut(_ shortcut: CustomShortcut?) {
    hotkeyRouter.updateShortcut(shortcut, for: .toggleRecording)
  }

  func retryModelLoading() {
    recordingController.retryModelLoading()
  }

  func requestMicrophone() async {
    await permissions.requestMicrophone()
  }

  func openAccessibilitySettings() {
    permissions.openAccessibilitySettings()
  }

  func copyRecordingText(_ text: String) {
    pasteboard.copy(text)
  }

  func openRecordingsFolder() {
    openRecordingsFolderAction()
  }

  func quitApplication() {
    quitApplicationAction()
  }
}
