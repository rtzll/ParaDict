import Foundation
import Testing

@testable import ParaDict

@MainActor
struct LivePreviewSessionTests {
  @Test func transientFailureRecoversOnTheNextScheduledPass() async {
    let transcriber = RecoveringLivePreviewTranscriber()
    let session = LivePreviewSession(
      clock: FastLivePreviewClock(),
      transcriptionPass: { samples, sampleRate, timeOffset in
        try await transcriber.transcribe(
          samples: samples,
          sampleRate: sampleRate,
          timeOffset: timeOffset
        )
      }
    )
    var updates: [StreamingPreviewUpdate] = []

    await session.startPrepared(inputSampleRate: 16_000) { update in
      updates.append(update)
    }
    session.send(audioData(sampleCount: 16_000))

    try? await Task.sleep(for: .milliseconds(80))
    await session.cancel()

    #expect(await transcriber.callCount >= 2)
    #expect(updates.contains(.partial("recovered preview")))
  }

  private func audioData(sampleCount: Int) -> Data {
    let samples = [Float](repeating: 0.1, count: sampleCount)
    return samples.withUnsafeBufferPointer { Data(buffer: $0) }
  }
}

private struct FastLivePreviewClock: LivePreviewClock {
  func wait(for interval: TimeInterval) async throws {
    try await Task.sleep(for: .milliseconds(10))
  }
}

private actor RecoveringLivePreviewTranscriber {
  private(set) var callCount = 0

  func transcribe(
    samples: [Float],
    sampleRate: Double,
    timeOffset: TimeInterval
  ) throws -> LivePreviewPassResult {
    callCount += 1
    if callCount == 1 {
      throw NSError(domain: "LivePreviewSessionTests", code: 1)
    }
    return LivePreviewPassResult(
      text: "recovered preview",
      words: [],
      confidence: 1
    )
  }
}
