import Foundation
import Testing

@testable import ParaDict

@MainActor
struct LivePreviewSessionTests {
  @Test func transientFailureRecoversOnTheNextScheduledPass() async {
    let transcriber = RecoveringLivePreviewTranscriber()
    let clock = ManualLivePreviewClock()
    let session = LivePreviewSession(
      clock: clock,
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
    await session.accept(audioData(sampleCount: 16_000))

    await clock.waitUntilScheduled()
    await clock.tick()
    await transcriber.waitUntilCallCount(1)

    await clock.waitUntilScheduled()
    await clock.tick()
    await transcriber.waitUntilCallCount(2)
    while !updates.contains(.partial("recovered preview")) {
      await Task.yield()
    }

    await clock.finish()
    await session.cancel()

    #expect(await transcriber.callCount >= 2)
    #expect(updates.contains(.partial("recovered preview")))
  }

  private func audioData(sampleCount: Int) -> Data {
    let samples = [Float](repeating: 0.1, count: sampleCount)
    return samples.withUnsafeBufferPointer { Data(buffer: $0) }
  }
}

private actor ManualLivePreviewClock: LivePreviewClock {
  private var waiters: [CheckedContinuation<Void, any Error>] = []
  private var isFinished = false

  func wait(for interval: TimeInterval) async throws {
    if isFinished { throw CancellationError() }
    try await withCheckedThrowingContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func waitUntilScheduled() async {
    while waiters.isEmpty {
      await Task.yield()
    }
  }

  func tick() {
    waiters.removeFirst().resume()
  }

  func finish() {
    isFinished = true
    let pending = waiters
    waiters.removeAll()
    for waiter in pending {
      waiter.resume(throwing: CancellationError())
    }
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

  func waitUntilCallCount(_ expected: Int) async {
    while callCount < expected {
      await Task.yield()
    }
  }
}
