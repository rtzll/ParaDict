@preconcurrency import FluidAudio
import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingControllerTests {
  @Test func usesInjectedConcreteDependencies() {
    let transcription = FakeTranscriptionProvider()
    let recorder = AudioRecorder()
    let deviceManager = AudioDeviceManager()
    let controller = RecordingController(
      recorder: recorder,
      deviceManager: deviceManager,
      transcriptionProvider: transcription,
      recordingPersistence: FakeRecordingPersistence(),
      analyticsRecording: FakeAnalyticsRecorder(),
      pasteboardWriter: FakePasteboardWriter()
    )

    #expect(controller.recorder === recorder)
    #expect(controller.deviceManager === deviceManager)
  }

  @Test func startRecordingWhenModelIsNotReadyShowsError() async {
    let toast = FakeToastPresenter()
    let transcription = FakeTranscriptionProvider()
    transcription.isInitialized = false
    let controller = makeController(toast: toast, transcriptionProvider: transcription)

    controller.startRecording()
    await settle()

    #expect(controller.recorder.state == .idle)
    #expect(controller.recordingSessionState == .idle)
    #expect(toast.errors.count == 1)
    #expect(toast.errors[0].title == "Model Not Ready")
  }

  @Test func stopAndTranscribeShortRecordingCancelsAndResetsState() async {
    let toast = FakeToastPresenter()
    let controller = makeController(toast: toast)
    var endedCount = 0
    controller.onRecordingEnded = { endedCount += 1 }
    controller.recorder.state = .recording
    controller.setRecordingSessionStateForTesting(.recording)
    controller.recorder.currentDuration = 0.5
    controller.partialTranscript = "partial text"
    controller.handleCancelRecordingShortcut()

    controller.stopAndTranscribe()
    await settle()

    #expect(controller.recorder.state == .idle)
    #expect(controller.recordingSessionState == .idle)
    #expect(controller.partialTranscript.isEmpty)
    #expect(controller.overlayHint == nil)
    #expect(endedCount == 1)
    #expect(toast.messages.isEmpty)
    #expect(toast.errors.isEmpty)
  }

  @Test func cancelRecordingShowsCancellationStatusAndClearsPartialTranscript() async {
    let toast = FakeToastPresenter()
    let controller = makeController(toast: toast)
    var endedCount = 0
    controller.onRecordingEnded = { endedCount += 1 }
    controller.recorder.state = .recording
    controller.setRecordingSessionStateForTesting(.recording)
    controller.partialTranscript = "partial text"
    controller.handleCancelRecordingShortcut()

    controller.cancelRecording()
    await settle()

    #expect(controller.recorder.state == .idle)
    #expect(controller.recordingSessionState == .idle)
    #expect(controller.partialTranscript.isEmpty)
    #expect(controller.overlayHint == nil)
    #expect(controller.overlayStatus?.kind == .warning)
    #expect(controller.overlayStatus?.title == "Recording Canceled")
    #expect(endedCount == 1)
  }

  @Test func recordingInterruptionResetsStateAndShowsErrorToast() async {
    let toast = FakeToastPresenter()
    let controller = makeController(toast: toast)
    var endedCount = 0
    controller.onRecordingEnded = { endedCount += 1 }
    controller.recorder.state = .recording
    controller.setRecordingSessionStateForTesting(.recording)
    controller.partialTranscript = "partial text"
    controller.overlayStatus = OverlayStatus(kind: .warning, title: "Existing", message: "status")
    controller.handleCancelRecordingShortcut()

    controller.recorder.onRecordingInterrupted?("Mic disconnected")
    await settle()

    #expect(controller.recorder.state == .idle)
    #expect(controller.recordingSessionState == .idle)
    #expect(controller.partialTranscript.isEmpty)
    #expect(controller.overlayStatus?.kind == .error)
    #expect(controller.overlayStatus?.title == "Recording Failed")
    #expect(controller.overlayStatus?.message == "Mic disconnected")
    #expect(controller.overlayHint == nil)
    #expect(endedCount == 1)
    #expect(toast.errors.isEmpty)
  }

  @Test func streamingPreviewStartupFailureShowsExplicitFeedback() {
    let toast = FakeToastPresenter()
    let controller = makeController(toast: toast)
    controller.recorder.state = .recording
    controller.setRecordingSessionStateForTesting(.recording)
    controller.partialTranscript = "partial text"
    controller.recorder.onAudioChunk = { _ in }

    controller.handleStreamingPreviewStartupFailure()

    #expect(controller.recorder.state == .recording)
    #expect(controller.recordingSessionState == .recording)
    #expect(controller.partialTranscript.isEmpty)
    #expect(controller.recorder.onAudioChunk == nil)
    #expect(controller.overlayStatus?.kind == .warning)
    #expect(controller.overlayStatus?.title == "Live Preview Unavailable")
    #expect(
      controller.overlayStatus?.message == "Recording will continue without transcript preview.")
    #expect(toast.messages.isEmpty)
  }

  @Test func cancelRecordingShortcutShowsAttachedOverlayHintInsteadOfToast() {
    let toast = FakeToastPresenter()
    let controller = makeController(toast: toast)
    controller.recorder.state = .recording
    controller.setRecordingSessionStateForTesting(.recording)

    controller.handleCancelRecordingShortcut()

    #expect(controller.overlayHint?.message == "Press Esc again to discard")
    #expect(toast.messages.isEmpty)
  }

  @Test func cancelRecordingShortcutUsesSessionStateAsSourceOfTruth() {
    let toast = FakeToastPresenter()
    let controller = makeController(toast: toast)
    controller.recorder.state = .idle
    controller.setRecordingSessionStateForTesting(.recording)

    controller.handleCancelRecordingShortcut()

    #expect(controller.overlayHint?.message == "Press Esc again to discard")
    #expect(toast.messages.isEmpty)
  }

  @Test func cancelRecordingShortcutSecondPressCancelsRecording() async {
    let toast = FakeToastPresenter()
    let controller = makeController(toast: toast)
    controller.recorder.state = .recording
    controller.setRecordingSessionStateForTesting(.recording)
    controller.partialTranscript = "partial text"

    controller.handleCancelRecordingShortcut()
    controller.handleCancelRecordingShortcut()
    await settle()

    #expect(controller.recorder.state == .idle)
    #expect(controller.recordingSessionState == .idle)
    #expect(controller.overlayHint == nil)
    #expect(controller.overlayStatus?.title == "Recording Canceled")
  }

  @Test func transcribeSuccessfulResultCopiesTextSavesRecordingAndTracksAnalytics() async throws {
    let toast = FakeToastPresenter()
    let transcription = FakeTranscriptionProvider()
    transcription.result = TranscriptionResult(
      text: "hello world",
      segments: [
        TranscriptionSegment(start: 0, end: 1.2, text: "hello world", words: nil)
      ],
      language: "en",
      duration: 0.4,
      model: "parakeet-test"
    )
    let recordings = FakeRecordingPersistence()
    let analytics = FakeAnalyticsRecorder()
    let pasteboard = FakePasteboardWriter()
    let controller = RecordingController(
      toast: toast,
      transcriptionProvider: transcription,
      recordingPersistence: recordings,
      analyticsRecording: analytics,
      pasteboardWriter: pasteboard
    )
    let audioURL = try makeAudioFile(named: "success.wav", size: 8)
    controller.recorder.state = .processing
    controller.setRecordingSessionStateForTesting(.processing)
    controller.partialTranscript = "partial text"
    controller.overlayStatus = OverlayStatus(kind: .warning, title: "Existing", message: "status")

    await controller.transcribe(
      CompletedRecordingCapture(
        audioURL: audioURL,
        recordingId: "recording-123",
        duration: 2.5,
        sampleRate: 16_000,
        inputDeviceName: "Test Mic"
      ))

    #expect(controller.recorder.state == .idle)
    #expect(controller.recordingSessionState == .idle)
    #expect(controller.partialTranscript.isEmpty)
    #expect(controller.overlayStatus == nil)
    #expect(toast.errors.isEmpty)
    #expect(pasteboard.copiedTexts == ["hello world"])
    #expect(analytics.calls.count == 1)
    #expect(analytics.calls[0].duration == 2.5)
    #expect(analytics.calls[0].wordCount == 2)
    #expect(recordings.completedRecordings.count == 1)
    #expect(recordings.failedRecordings.isEmpty)
    #expect(recordings.completedRecordings[0].id == "recording-123")
    #expect(recordings.completedRecordings[0].recording.fileSize == 8)
    #expect(recordings.completedRecordings[0].transcription?.text == "hello world")
  }

  @Test func transcribeEmptyResultClearsStateAndShowsErrorWithoutPersisting() async throws {
    let toast = FakeToastPresenter()
    let transcription = FakeTranscriptionProvider()
    transcription.result = TranscriptionResult(
      text: "",
      segments: [],
      language: "en",
      duration: 0.2,
      model: "parakeet-test"
    )
    let recordings = FakeRecordingPersistence()
    let analytics = FakeAnalyticsRecorder()
    let pasteboard = FakePasteboardWriter()
    let controller = RecordingController(
      toast: toast,
      transcriptionProvider: transcription,
      recordingPersistence: recordings,
      analyticsRecording: analytics,
      pasteboardWriter: pasteboard
    )
    let audioURL = try makeAudioFile(named: "empty.wav", size: 4)
    controller.recorder.state = .processing
    controller.setRecordingSessionStateForTesting(.processing)
    controller.partialTranscript = "partial text"
    controller.overlayStatus = OverlayStatus(kind: .warning, title: "Existing", message: "status")

    await controller.transcribe(
      CompletedRecordingCapture(
        audioURL: audioURL,
        recordingId: "recording-empty",
        duration: 1.4,
        sampleRate: 44_100,
        inputDeviceName: "Test Mic"
      ))

    #expect(controller.recorder.state == .idle)
    #expect(controller.recordingSessionState == .idle)
    #expect(controller.partialTranscript.isEmpty)
    #expect(controller.overlayStatus?.kind == .error)
    #expect(controller.overlayStatus?.title == "Empty Transcription")
    #expect(controller.overlayStatus?.message == "No speech detected in recording.")
    #expect(toast.errors.isEmpty)
    #expect(pasteboard.copiedTexts.isEmpty)
    #expect(analytics.calls.isEmpty)
    #expect(recordings.completedRecordings.isEmpty)
    #expect(recordings.failedRecordings.isEmpty)
  }

  @Test func transcribeFailureShowsErrorAndSavesFailedRecording() async throws {
    let toast = FakeToastPresenter()
    let transcription = FakeTranscriptionProvider()
    transcription.error = NSError(
      domain: "RecordingControllerTests",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "transcriber exploded"]
    )
    let recordings = FakeRecordingPersistence()
    let analytics = FakeAnalyticsRecorder()
    let pasteboard = FakePasteboardWriter()
    let controller = RecordingController(
      toast: toast,
      transcriptionProvider: transcription,
      recordingPersistence: recordings,
      analyticsRecording: analytics,
      pasteboardWriter: pasteboard
    )
    let audioURL = try makeAudioFile(named: "failure.wav", size: 6)
    controller.recorder.state = .processing
    controller.setRecordingSessionStateForTesting(.processing)
    controller.partialTranscript = "partial text"
    controller.overlayStatus = OverlayStatus(kind: .warning, title: "Existing", message: "status")

    await controller.transcribe(
      CompletedRecordingCapture(
        audioURL: audioURL,
        recordingId: "recording-failure",
        duration: 3.1,
        sampleRate: 48_000,
        inputDeviceName: "Desk Mic"
      ))

    #expect(controller.recorder.state == .idle)
    #expect(controller.recordingSessionState == .idle)
    #expect(controller.partialTranscript.isEmpty)
    #expect(controller.overlayStatus?.kind == .error)
    #expect(controller.overlayStatus?.title == "Transcription Failed")
    #expect(controller.overlayStatus?.message == "transcriber exploded")
    #expect(toast.errors.isEmpty)
    #expect(pasteboard.copiedTexts.isEmpty)
    #expect(analytics.calls.isEmpty)
    #expect(recordings.completedRecordings.isEmpty)
    #expect(recordings.failedRecordings.count == 1)
    #expect(recordings.failedRecordings[0].id == "recording-failure")
    #expect(recordings.failedRecordings[0].status == .failed)
    #expect(recordings.failedRecordings[0].transcription == nil)
  }

  private func settle() async {
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(20))
    await Task.yield()
  }

  private func makeController(
    toast: FakeToastPresenter = FakeToastPresenter(),
    transcriptionProvider: FakeTranscriptionProvider = FakeTranscriptionProvider()
  ) -> RecordingController {
    RecordingController(
      toast: toast,
      transcriptionProvider: transcriptionProvider,
      recordingPersistence: FakeRecordingPersistence(),
      analyticsRecording: FakeAnalyticsRecorder(),
      pasteboardWriter: FakePasteboardWriter()
    )
  }

  private func makeAudioFile(named name: String, size: Int) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ParaDictTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try Data(repeating: 0xAB, count: size).write(to: url)
    return url
  }
}

@MainActor
private final class FakeToastPresenter: ToastPresenting, @unchecked Sendable {
  struct PresentedMessage {
    let toast: ToastMessage
    let anchor: ToastWindowController.Anchor
  }

  private(set) var messages: [PresentedMessage] = []
  private(set) var errors: [(title: String, message: String?)] = []

  func show(_ toast: ToastMessage, anchor: ToastWindowController.Anchor) {
    messages.append(PresentedMessage(toast: toast, anchor: anchor))
  }

  func showError(title: String, message: String?) {
    errors.append((title, message))
  }
}

@MainActor
private final class FakeTranscriptionProvider: TranscriptionProviding, @unchecked Sendable {
  var isInitialized: Bool = true
  var result = TranscriptionResult(
    text: "",
    segments: [],
    language: "en",
    duration: 0,
    model: "fake"
  )
  var error: Error?

  func initialize() async throws {}

  func models() async throws -> AsrModels {
    fatalError("Unused in RecordingControllerTests")
  }

  func transcribe(audioURL: URL) async throws -> TranscriptionResult {
    if let error {
      throw error
    }
    return result
  }
}

@MainActor
private final class FakeRecordingPersistence: RecordingPersisting, @unchecked Sendable {
  private(set) var completedRecordings: [Recording] = []
  private(set) var failedRecordings: [Recording] = []

  func saveWithExistingAudio(_ recording: Recording) async throws {
    completedRecordings.append(recording)
  }

  func saveFailedRecording(_ recording: Recording) async throws {
    failedRecordings.append(recording)
  }
}

@MainActor
private final class FakeAnalyticsRecorder: AnalyticsRecording, @unchecked Sendable {
  struct Call {
    let duration: TimeInterval
    let wordCount: Int
  }

  private(set) var calls: [Call] = []

  func record(duration: TimeInterval, wordCount: Int) async {
    calls.append(Call(duration: duration, wordCount: wordCount))
  }
}

private final class FakePasteboardWriter: PasteboardWriting, @unchecked Sendable {
  private(set) var copiedTexts: [String] = []

  func copyAndPaste(_ text: String) {
    copiedTexts.append(text)
  }
}
