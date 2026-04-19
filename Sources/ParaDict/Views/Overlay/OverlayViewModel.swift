import Foundation
import Observation

@Observable
@MainActor
final class OverlayViewModel: Sendable {
  private let recordingController: RecordingController

  init(recordingController: RecordingController) {
    self.recordingController = recordingController
  }

  var state: RecordingState { recordingController.displayState }
  var duration: TimeInterval { recordingController.recorder.currentDuration }
  var meterLevel: Double { recordingController.recorder.meterLevel }
  var partialTranscript: String { recordingController.partialTranscript }
  var overlayStatus: OverlayStatus? { recordingController.overlayStatus }
  var overlayHint: OverlayHint? { recordingController.overlayHint }
}
