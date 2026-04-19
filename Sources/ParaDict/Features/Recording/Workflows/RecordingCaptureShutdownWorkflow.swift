import Foundation

@MainActor
protocol RecordingCaptureStopping: AnyObject {
  var currentDuration: TimeInterval { get }
  var actualSampleRate: Double { get }
  var actualInputDeviceName: String { get }
  func stopRecording() async -> URL?
  func cancelRecording() async
  func reset()
}

@MainActor
final class RecordingCaptureShutdownWorkflow: Sendable {
  private let recorder: RecordingCaptureStopping
  private let sessionRuntime: RecordingSessionRuntime
  private let clearRecordingPresentation: @MainActor () -> Void
  private let clearOverlayStatus: @MainActor () -> Void

  init(
    recorder: RecordingCaptureStopping,
    sessionRuntime: RecordingSessionRuntime,
    clearRecordingPresentation: @escaping @MainActor () -> Void,
    clearOverlayStatus: @escaping @MainActor () -> Void
  ) {
    self.recorder = recorder
    self.sessionRuntime = sessionRuntime
    self.clearRecordingPresentation = clearRecordingPresentation
    self.clearOverlayStatus = clearOverlayStatus
  }

  func discardActiveCapture() async {
    await cancelStreamingSession()
    clearRecordingPresentation()
    await recorder.cancelRecording()
    recorder.reset()
    sessionRuntime.clearActiveCapture()
    sessionRuntime.finishRecordingCancellation()
  }

  func stopCaptureForTranscription() async -> CompletedRecordingCapture? {
    let duration = recorder.currentDuration
    let sampleRate = recorder.actualSampleRate
    let inputDeviceName = recorder.actualInputDeviceName

    guard duration >= 1.0 else {
      await discardActiveCapture()
      return nil
    }

    guard let audioURL = await recorder.stopRecording() else {
      await cancelStreamingSession()
      clearRecordingPresentation()
      recorder.reset()
      sessionRuntime.clearActiveCapture()
      sessionRuntime.finishRecordingCancellation()
      return nil
    }

    await cancelStreamingSession()
    clearOverlayStatus()
    sessionRuntime.beginProcessing()

    let recordingId = sessionRuntime.currentRecordingId ?? Recording.generateId()
    sessionRuntime.clearActiveCapture()

    return CompletedRecordingCapture(
      audioURL: audioURL,
      recordingId: recordingId,
      duration: duration,
      sampleRate: sampleRate,
      inputDeviceName: inputDeviceName
    )
  }

  func stopCaptureForCancellation() async -> URL? {
    let audioURL = await recorder.stopRecording()
    await cancelStreamingSession()
    clearRecordingPresentation()
    recorder.reset()
    sessionRuntime.clearActiveCapture()
    sessionRuntime.finishRecordingCancellation()
    return audioURL
  }

  private func cancelStreamingSession() async {
    let session = sessionRuntime.takeActiveStreamingSession()
    await session?.cancel()
  }
}

extension AudioRecorder: RecordingCaptureStopping {}
