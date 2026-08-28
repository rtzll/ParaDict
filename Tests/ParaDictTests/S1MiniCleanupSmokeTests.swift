import Foundation
import Metal
import Testing

@testable import ParaDict

private let s1SmokeTestEnabled =
  ProcessInfo.processInfo.environment["PARADICT_S1_SMOKE_TEST"] == "1"
  && MTLCreateSystemDefaultDevice() != nil

/// Exercises the real S1-mini load + cleanup path (downloads the model on
/// first run). Opt in with PARADICT_S1_SMOKE_TEST=1 to keep it out of the
/// default test run:
///
///     just s1-smoke-test
@MainActor
@Suite("S1-mini cleanup smoke test", .enabled(if: s1SmokeTestEnabled))
struct S1MiniCleanupSmokeTests {
  @Test func cleanupSampleTranscripts() async throws {
    let service = try await makeReadyService()
    let samples = [
      (
        input: "so um i need to like send the the report by uh friday no wait make that thursday",
        expected: "So I need to send the report by Thursday."
      ),
      (
        input: "send it to support at superwhisper dot com",
        expected: "Send it to support@superwhisper.com."
      ),
      (input: "um", expected: ""),
    ]

    for sample in samples {
      let start = Date()
      let result = await service.cleanup(sample.input)
      let elapsed = Date().timeIntervalSince(start)
      print("(\(String(format: "%.2f", elapsed))s) IN : \(sample.input)")
      switch result {
      case .cleaned(let text):
        print("            OUT: \(text.debugDescription)")
        #expect(text == sample.expected)
      case .unavailable:
        Issue.record("Cleanup was unavailable")
      }
    }
  }

  private func makeReadyService() async throws -> S1MiniCleanupService {
    let service = S1MiniCleanupService(enabled: true)
    let loadStart = Date()
    service.prepare()
    let deadline = ContinuousClock.now.advanced(by: .seconds(120))

    while service.state == .preparing {
      guard ContinuousClock.now < deadline else {
        throw SmokeTestError.timedOutWaitingForModel
      }
      try await Task.sleep(for: .milliseconds(200))
    }
    guard case .ready = service.state else {
      throw SmokeTestError.modelFailedToLoad(String(describing: service.state))
    }
    print("Load time: \(String(format: "%.1f", Date().timeIntervalSince(loadStart)))s")
    return service
  }

  private enum SmokeTestError: Error {
    case timedOutWaitingForModel
    case modelFailedToLoad(String)
  }
}
