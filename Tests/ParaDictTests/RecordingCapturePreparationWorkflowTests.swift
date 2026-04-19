@preconcurrency import FluidAudio
import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingCapturePreparationWorkflowTests {
  @Test func returnsNoInputDeviceWhenResolverCannotResolve() {
    let workflow = RecordingCapturePreparationWorkflow(
      deviceResolver: WorkflowDeviceResolver(resolvedDevice: nil),
      modelProvider: WorkflowModelsProvider()
    )

    let outcome = workflow.preparePendingSession(recordingId: "recording-123")

    guard case .noInputDevice = outcome else {
      Issue.record("Expected no-input-device outcome")
      return
    }
  }

  @Test func preparesPendingSessionAndTracksFallbackState() {
    let workflow = RecordingCapturePreparationWorkflow(
      deviceResolver: WorkflowDeviceResolver(
        resolvedDevice: ResolvedRecordingDevice(
          deviceID: 42,
          resolvedDeviceName: "Built-in Mic",
          didFallbackToSystemDefault: true,
          requestedMode: .specificDevice
        )),
      modelProvider: WorkflowModelsProvider()
    )

    let outcome = workflow.preparePendingSession(recordingId: "recording-123")

    guard case .ready(let preparation) = outcome else {
      Issue.record("Expected prepared session")
      return
    }

    #expect(preparation.didFallbackToSystemDefault)
    #expect(preparation.session.recordingId == "recording-123")
    #expect(preparation.session.audioURL.lastPathComponent == "audio.wav")
    #expect(
      preparation.session.audioURL.deletingLastPathComponent().lastPathComponent == "recording-123")
    #expect(preparation.session.resolvedDevice.deviceID == 42)
  }

  @Test func previewStartReturnsFailureWhenModelsCannotLoad() async {
    let modelsProvider = WorkflowModelsProvider()
    modelsProvider.modelsError = NSError(
      domain: "RecordingCapturePreparationWorkflowTests",
      code: 3,
      userInfo: [NSLocalizedDescriptionKey: "models unavailable"]
    )
    let workflow = RecordingCapturePreparationWorkflow(
      deviceResolver: WorkflowDeviceResolver(
        resolvedDevice: ResolvedRecordingDevice(
          deviceID: 1,
          resolvedDeviceName: "Mic",
          didFallbackToSystemDefault: false,
          requestedMode: .systemDefault
        )),
      modelProvider: modelsProvider
    )

    guard
      case .ready(let preparation) = workflow.preparePendingSession(recordingId: "recording-123")
    else {
      Issue.record("Expected prepared session")
      return
    }

    let result = await workflow.startStreamingPreview(
      for: preparation.session,
      inputSampleRate: 16_000
    ) { _ in }

    switch result {
    case .success:
      Issue.record("Expected preview start failure")
    case .failure(let error):
      #expect(error.localizedDescription == "models unavailable")
    }
  }
}

@MainActor
private final class WorkflowDeviceResolver: RecordingDeviceResolving, @unchecked Sendable {
  let resolvedDevice: ResolvedRecordingDevice?

  init(resolvedDevice: ResolvedRecordingDevice?) {
    self.resolvedDevice = resolvedDevice
  }

  func resolveRecordingDevice() -> ResolvedRecordingDevice? {
    resolvedDevice
  }
}

@MainActor
private final class WorkflowModelsProvider: TranscriptionProviding, @unchecked Sendable {
  var isInitialized = true
  var modelsError: Error?

  func initialize() async throws {}

  func models() async throws -> AsrModels {
    if let modelsError {
      throw modelsError
    }
    fatalError("Unused success path in RecordingCapturePreparationWorkflowTests")
  }

  func transcribe(audioURL: URL) async throws -> TranscriptionResult {
    fatalError("Unused in RecordingCapturePreparationWorkflowTests")
  }
}
