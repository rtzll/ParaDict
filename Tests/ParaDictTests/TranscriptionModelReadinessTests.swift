@preconcurrency import FluidAudio
import Foundation
import Testing

@testable import ParaDict

@MainActor
struct TranscriptionModelReadinessTests {
  @Test func preloadPublishesLoadingThenReady() async {
    let provider = ReadinessTranscriptionProvider()
    provider.behaviors = [.succeed]
    let readiness = TranscriptionModelReadiness(provider: provider)

    readiness.preload()

    #expect(readiness.state == .loading)

    await settle()

    #expect(readiness.state == .loaded)
    #expect(readiness.isReadyForRecording)
    #expect(readiness.menuPresentation.title == "Ready")
    #expect(provider.initializeCallCount == 1)
  }

  @Test func failedPreloadKeepsUserVisibleFailureForStartRecording() async {
    let provider = ReadinessTranscriptionProvider()
    provider.behaviors = [
      .fail(
        NSError(
          domain: "TranscriptionModelReadinessTests",
          code: 7,
          userInfo: [NSLocalizedDescriptionKey: "download failed"]
        ))
    ]
    let readiness = TranscriptionModelReadiness(provider: provider)

    readiness.preload()
    await settle()

    #expect(
      readiness.state
        == .failed(ModelReadinessFailure(title: "Model Load Failed", message: "download failed")))
    #expect(readiness.menuPresentation.title == "Model Load Failed")
    #expect(readiness.menuPresentation.retryTitle == "Retry")

    let failure = readiness.recordingStartFailure()
    #expect(failure?.title == "Model Load Failed")
    #expect(failure?.message == "download failed Try Retry from the menu bar.")
  }

  @Test func retryCancelsHungLoadAndCanSucceed() async {
    let provider = ReadinessTranscriptionProvider()
    provider.behaviors = [.hangUntilCancelled, .succeed]
    let readiness = TranscriptionModelReadiness(provider: provider)

    readiness.preload()
    await settle()

    #expect(readiness.state == .loading)
    #expect(provider.initializeCallCount == 1)

    readiness.retry()
    await settle()

    #expect(readiness.state == .loaded)
    #expect(provider.initializeCallCount == 2)
    #expect(provider.resetCallCount == 1)
  }

  private func settle() async {
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(20))
    await Task.yield()
  }
}

@MainActor
private final class ReadinessTranscriptionProvider: TranscriptionProviding,
  TranscriptionModelLoadingResetting, @unchecked Sendable
{
  enum Behavior {
    case succeed
    case fail(Error)
    case hangUntilCancelled
  }

  var isInitialized = false
  var behaviors: [Behavior] = []
  private(set) var initializeCallCount = 0
  private(set) var resetCallCount = 0

  func initialize() async throws {
    initializeCallCount += 1
    let behavior = behaviors.isEmpty ? .succeed : behaviors.removeFirst()

    switch behavior {
    case .succeed:
      isInitialized = true
    case .fail(let error):
      throw error
    case .hangUntilCancelled:
      while !Task.isCancelled {
        try await Task.sleep(for: .milliseconds(50))
      }
      throw CancellationError()
    }
  }

  func resetModelLoading() {
    resetCallCount += 1
    isInitialized = false
  }

  func models() async throws -> AsrModels {
    fatalError("Unused in TranscriptionModelReadinessTests")
  }

  func transcribe(audioURL: URL) async throws -> TranscriptionResult {
    fatalError("Unused in TranscriptionModelReadinessTests")
  }
}
