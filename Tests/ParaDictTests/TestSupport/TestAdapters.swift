@preconcurrency import FluidAudio
import Foundation

@testable import ParaDict

@MainActor
final class TestToastPresenter: ToastPresenting, @unchecked Sendable {
  struct PresentedMessage {
    let toast: ToastMessage
    let anchor: ToastWindowController.Anchor
  }

  private(set) var messages: [PresentedMessage] = []
  private(set) var errors: [(title: String, message: String?)] = []

  func show(_ toast: ToastMessage, anchor: ToastWindowController.Anchor) {
    messages.append(PresentedMessage(toast: toast, anchor: anchor))
    if toast.type == .error {
      errors.append((toast.title, toast.message))
    }
  }

  func showError(title: String, message: String?) {
    errors.append((title, message))
  }
}

@MainActor
final class TestTranscriptionProvider: TranscriptionProviding, @unchecked Sendable {
  var isInitialized = true
  var initializeError: Error?
  var result = TranscriptionResult(
    text: "",
    segments: [],
    language: "en",
    duration: 0,
    model: "fake"
  )
  var error: Error?
  var modelsError: Error?
  private(set) var initializeCallCount = 0

  func initialize() async throws {
    initializeCallCount += 1
    if let initializeError {
      throw initializeError
    }
    isInitialized = true
  }

  func models() async throws -> AsrModels {
    if let modelsError {
      throw modelsError
    }
    fatalError("Set modelsError or use a specialized models provider for successful model access")
  }

  func transcribe(audioURL: URL) async throws -> TranscriptionResult {
    if let error {
      throw error
    }
    return result
  }
}

@MainActor
final class TestRecordingPersistence: RecordingPersisting, @unchecked Sendable {
  var completedSaveError: Error?
  var failedSaveError: Error?
  private(set) var completedRecordings: [Recording] = []
  private(set) var failedRecordings: [Recording] = []

  func saveWithExistingAudio(_ recording: Recording) async throws {
    if let completedSaveError {
      throw completedSaveError
    }
    completedRecordings.append(recording)
  }

  func saveFailedRecording(_ recording: Recording) async throws {
    if let failedSaveError {
      throw failedSaveError
    }
    failedRecordings.append(recording)
  }
}

@MainActor
final class TestAnalyticsRecorder: AnalyticsRecording, @unchecked Sendable {
  struct Call {
    let duration: TimeInterval
    let wordCount: Int
  }

  private(set) var calls: [Call] = []

  func record(duration: TimeInterval, wordCount: Int) async {
    calls.append(Call(duration: duration, wordCount: wordCount))
  }
}

final class TestPasteboardWriter: PasteboardWriting, @unchecked Sendable {
  private(set) var copiedTexts: [String] = []

  func copyAndPaste(_ text: String) {
    copiedTexts.append(text)
  }
}

@MainActor
final class TestRecordingFeedbackPresenter: RecordingFeedbackPresenting, @unchecked Sendable {
  private(set) var feedback: [RecordingFeedback] = []
  private(set) var clearOverlayStatusCallCount = 0

  func present(_ feedback: RecordingFeedback) {
    self.feedback.append(feedback)
  }

  func clearOverlayStatus() {
    clearOverlayStatusCallCount += 1
  }
}
