import Foundation
import Observation

struct OverlaySnapshot: Equatable, Sendable {
  let state: RecordingState
  let duration: TimeInterval
  let meterLevel: Double
  let partialTranscript: String
  let status: OverlayStatus?
  let hint: OverlayHint?
}

@Observable
@MainActor
final class OverlayViewModel: Sendable {
  private let recordingController: RecordingController

  init(recordingController: RecordingController) {
    self.recordingController = recordingController
  }

  var snapshot: OverlaySnapshot {
    OverlaySnapshot(
      state: recordingController.displayState,
      duration: recordingController.recorder.currentDuration,
      meterLevel: recordingController.recorder.meterLevel,
      partialTranscript: recordingController.partialTranscript,
      status: recordingController.overlayStatus,
      hint: recordingController.overlayHint
    )
  }
}
