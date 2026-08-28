import Foundation
import Testing

@testable import ParaDict

@MainActor
struct TranscriptChunkerTests {
  @Test func keepsSentenceBoundariesWhenSplittingLongInput() async {
    let chunker = TranscriptChunker(maximumTokens: 3)

    let chunks = await chunker.chunks(for: "One two. Three four.") { text in
      text.split(whereSeparator: { $0.isWhitespace }).count
    }

    #expect(chunks == ["One two.", "Three four."])
  }

  @Test func splitsAnOversizedSentenceAtWordBoundaries() async {
    let chunker = TranscriptChunker(maximumTokens: 2)

    let chunks = await chunker.chunks(for: "one two three four five") { text in
      text.split(whereSeparator: { $0.isWhitespace }).count
    }

    #expect(chunks == ["one two", "three four", "five"])
  }
}

@MainActor
struct S1MiniCleanupServiceTests {
  @Test func outputBudgetDoesNotTruncateTheDocumentedSafetyMargin() {
    #expect(S1MiniCleanupService.outputTokenBudget(forInputTokens: 900) == 1_202)
  }

  @Test func persistedEnabledSettingStartsModelPreparationOnInitialization() async throws {
    let suiteName = "S1MiniCleanupServiceTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: "TranscriptCleanupEnabled")

    let service = S1MiniCleanupService(
      defaults: defaults,
      modelLoader: {
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
      }
    )

    #expect(service.isEnabled)
    #expect(service.state == .preparing)

    service.setEnabled(false)
    #expect(service.state == .idle)
  }

  @Test func modelLoadFailureIsExposedWithoutCrashing() async throws {
    let service = S1MiniCleanupService(
      enabled: true,
      modelLoader: {
        throw TestLoadError.failed
      }
    )

    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while service.state == .preparing, ContinuousClock.now < deadline {
      await Task.yield()
    }

    #expect(service.state == .failed("test load failed"))
  }

  private enum TestLoadError: LocalizedError {
    case failed

    var errorDescription: String? { "test load failed" }
  }
}
