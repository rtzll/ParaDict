struct RecordingHeaderPresentation: Equatable, Sendable {
  let title: String
  let detail: String?

  static func make(
    recordingState: RecordingState,
    modelReadiness: ModelReadinessMenuPresentation,
    allPermissionsGranted: Bool,
    shortcut: CustomShortcut?
  ) -> RecordingHeaderPresentation {
    guard allPermissionsGranted else {
      return RecordingHeaderPresentation(
        title: "Finish Setup",
        detail: "Grant access below to start dictating"
      )
    }

    switch recordingState {
    case .idle:
      return RecordingHeaderPresentation(
        title: modelReadiness.title,
        detail: readyInstruction(modelReadiness: modelReadiness, shortcut: shortcut)
      )
    case .recording:
      return RecordingHeaderPresentation(title: "Recording", detail: nil)
    case .processing:
      return RecordingHeaderPresentation(title: "Transcribing...", detail: nil)
    case .error(let message):
      return RecordingHeaderPresentation(title: message, detail: nil)
    }
  }

  private static func readyInstruction(
    modelReadiness: ModelReadinessMenuPresentation,
    shortcut: CustomShortcut?
  ) -> String? {
    guard case .ready = modelReadiness.tone else { return nil }
    guard let shortcut else {
      return "Set a shortcut below to start dictating"
    }
    return "Press \(shortcut.compactDisplayString) to dictate"
  }
}
