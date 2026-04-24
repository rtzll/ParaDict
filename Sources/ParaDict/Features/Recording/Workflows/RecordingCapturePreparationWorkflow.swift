@preconcurrency import FluidAudio
import Foundation

@MainActor
protocol RecordingDeviceResolving: AnyObject {
  func resolveRecordingDevice() -> ResolvedRecordingDevice?
}

struct PendingRecordingSession {
  let recordingId: String
  let resolvedDevice: ResolvedRecordingDevice
  let audioURL: URL
  let streamingSession: ParakeetStreamingSession
}

struct RecordingSessionPreparation {
  let session: PendingRecordingSession
  let didFallbackToSystemDefault: Bool
}

enum RecordingSessionPreparationOutcome {
  case ready(RecordingSessionPreparation)
  case noInputDevice
}

@MainActor
final class RecordingCapturePreparationWorkflow: Sendable {
  private let deviceResolver: RecordingDeviceResolving
  private let modelProvider: TranscriptionProviding
  private let makeStreamingSession: @Sendable () -> ParakeetStreamingSession

  init(
    deviceResolver: RecordingDeviceResolving,
    modelProvider: TranscriptionProviding,
    makeStreamingSession: @escaping @Sendable () -> ParakeetStreamingSession = {
      ParakeetStreamingSession()
    }
  ) {
    self.deviceResolver = deviceResolver
    self.modelProvider = modelProvider
    self.makeStreamingSession = makeStreamingSession
  }

  func preparePendingSession(recordingId: String) -> RecordingSessionPreparationOutcome {
    guard let resolvedDevice = deviceResolver.resolveRecordingDevice() else {
      return .noInputDevice
    }

    let dir = Recording.baseDirectory.appendingPathComponent(recordingId)
    let audioURL = dir.appendingPathComponent("audio.wav")
    let session = PendingRecordingSession(
      recordingId: recordingId,
      resolvedDevice: resolvedDevice,
      audioURL: audioURL,
      streamingSession: makeStreamingSession()
    )

    return .ready(
      RecordingSessionPreparation(
        session: session,
        didFallbackToSystemDefault: resolvedDevice.requestedMode == .specificDevice
          && resolvedDevice.didFallbackToSystemDefault
      ))
  }

  func startStreamingPreview(
    for session: PendingRecordingSession,
    inputSampleRate: Double,
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) async -> Result<Void, Error> {
    do {
      let models = try await modelProvider.models()
      try await session.streamingSession.start(
        models: models,
        inputSampleRate: inputSampleRate,
        onPreviewUpdate: onPreviewUpdate
      )
      return .success(())
    } catch {
      await session.streamingSession.cancel()
      return .failure(error)
    }
  }
}

extension AudioDeviceManager: RecordingDeviceResolving {}
