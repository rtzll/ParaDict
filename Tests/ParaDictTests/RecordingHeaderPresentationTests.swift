import Carbon.HIToolbox
import Testing

@testable import ParaDict

struct RecordingHeaderPresentationTests {
  @Test func readyStateExplainsHowToStartDictating() {
    let presentation = RecordingHeaderPresentation.make(
      recordingState: .idle,
      modelReadiness: readyModel,
      allPermissionsGranted: true,
      shortcut: CustomShortcut(keyCode: UInt16(kVK_Function))
    )

    #expect(presentation.title == "Ready")
    #expect(presentation.detail == "Press Fn to dictate")
  }

  @Test func readyStateExplainsWhenShortcutStillNeedsConfiguration() {
    let presentation = RecordingHeaderPresentation.make(
      recordingState: .idle,
      modelReadiness: readyModel,
      allPermissionsGranted: true,
      shortcut: nil
    )

    #expect(presentation.title == "Ready")
    #expect(presentation.detail == "Set a shortcut below to start dictating")
  }

  @Test func incompletePermissionsFocusTheHeaderOnSetup() {
    let presentation = RecordingHeaderPresentation.make(
      recordingState: .idle,
      modelReadiness: readyModel,
      allPermissionsGranted: false,
      shortcut: CustomShortcut(keyCode: UInt16(kVK_Function))
    )

    #expect(presentation.title == "Finish Setup")
    #expect(presentation.detail == "Grant access below to start dictating")
  }

  private var readyModel: ModelReadinessMenuPresentation {
    ModelReadinessMenuPresentation(
      title: "Ready",
      systemImage: "waveform",
      tone: .ready,
      showsProgress: false,
      retryTitle: nil
    )
  }
}
