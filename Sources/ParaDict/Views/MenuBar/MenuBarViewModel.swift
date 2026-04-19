import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class MenuBarViewModel: Sendable {
  private let recordingController: RecordingController
  private let recordingStore: RecordingStore
  private let analyticsStore: AnalyticsStore
  private let permissions: PermissionsManager
  private let pasteboard: PasteboardService
  private let openRecordingsFolderAction: @MainActor () -> Void
  private let quitApplicationAction: @MainActor () -> Void

  init(
    recordingController: RecordingController,
    recordingStore: RecordingStore,
    analyticsStore: AnalyticsStore,
    permissions: PermissionsManager,
    pasteboard: PasteboardService,
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
    self.recordingStore = recordingStore
    self.analyticsStore = analyticsStore
    self.permissions = permissions
    self.pasteboard = pasteboard
    self.openRecordingsFolderAction = openRecordingsFolderAction
    self.quitApplicationAction = quitApplicationAction
  }

  var recorder: AudioRecorder { recordingController.recorder }
  var recordingState: RecordingState { recordingController.displayState }
  var currentDuration: TimeInterval { recordingController.recorder.currentDuration }
  var isModelLoaded: Bool { recordingController.isModelLoaded }
  var allPermissionsGranted: Bool { permissions.allGranted }
  var accessibilityGranted: Bool { permissions.accessibilityGranted }
  var microphoneGranted: Bool { permissions.microphoneGranted }
  var inputMode: MicInputMode { recordingController.deviceManager.inputMode }
  var selectedDeviceUID: String? { recordingController.deviceManager.selectedDeviceUID }
  var systemDefaultDeviceName: String { recordingController.deviceManager.systemDefaultDeviceName }
  var effectiveDeviceName: String { recordingController.deviceManager.effectiveDeviceName }
  var isSelectedDeviceAvailable: Bool {
    recordingController.deviceManager.isSelectedDeviceAvailable
  }
  var availableDevices: [AudioInputDevice] { recordingController.deviceManager.availableDevices }
  var recentHistoryItems: [Recording] { recordingStore.recentHistoryItems }
  var formattedRecordings: String { analyticsStore.formattedRecordings }
  var formattedSpeakingTime: String { analyticsStore.formattedSpeakingTime }
  var formattedWords: String { analyticsStore.formattedWords }
  var averageWPM: String { "\(analyticsStore.averageWPM)" }
  var toggleRecordingShortcut: CustomShortcut? { CustomShortcutStorage.get(.toggleRecording) }

  func selectDevice(_ device: AudioInputDevice) {
    recordingController.deviceManager.selectDevice(device)
  }

  func selectSystemDefaultMicrophone() {
    recordingController.deviceManager.selectSystemDefault()
  }

  func updateToggleRecordingShortcut(_ shortcut: CustomShortcut?) {
    CustomShortcutStorage.set(shortcut, for: .toggleRecording)
    recordingController.reloadShortcuts()
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
