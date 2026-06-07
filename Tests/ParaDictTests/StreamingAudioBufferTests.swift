import Foundation
import Testing

@testable import ParaDict

struct StreamingAudioBufferTests {
  @Test func appendsChunksAndBuildsWindowFromSeekTime() throws {
    var buffer = StreamingAudioBuffer()
    buffer.append(chunk: data((0..<20).map(Float.init)))

    #expect(buffer.absoluteSampleCount == 20)
    #expect(buffer.hasEnoughAudioToProcess(inputSampleRate: 10, minNewAudioSeconds: 0.5))

    let window = try #require(
      buffer.transcriptionWindow(
        startingAt: 0.5,
        inputSampleRate: 10,
        trailingSilenceSeconds: 0
      ))

    #expect(window.samples.first == 5)
    #expect(window.samples.last == 19)
    #expect(window.timeOffset == 0.5)
  }

  @Test func processedSamplesGateFuturePassesUntilEnoughNewAudioArrives() {
    var buffer = StreamingAudioBuffer()
    buffer.append(chunk: data((0..<20).map(Float.init)))
    buffer.markProcessed(upTo: buffer.absoluteSampleCount)

    #expect(!buffer.hasEnoughAudioToProcess(inputSampleRate: 10, minNewAudioSeconds: 0.5))

    buffer.append(chunk: data((20..<24).map(Float.init)))
    #expect(!buffer.hasEnoughAudioToProcess(inputSampleRate: 10, minNewAudioSeconds: 0.5))

    buffer.append(chunk: data([24]))
    #expect(buffer.hasEnoughAudioToProcess(inputSampleRate: 10, minNewAudioSeconds: 0.5))
  }

  @Test func trimmingPreservesAbsoluteTimelineForFutureWindows() throws {
    var buffer = StreamingAudioBuffer()
    buffer.append(chunk: data((0..<20).map(Float.init)))

    buffer.trim(beforeAbsoluteSample: 8)

    #expect(buffer.trimmedSampleCount == 8)
    #expect(buffer.absoluteSampleCount == 20)

    let window = try #require(
      buffer.transcriptionWindow(
        startingAt: 0.8,
        inputSampleRate: 10,
        trailingSilenceSeconds: 0
      ))

    #expect(window.samples.first == 8)
    #expect(window.timeOffset == 0.8)
  }

  private func data(_ samples: [Float]) -> Data {
    samples.withUnsafeBufferPointer { Data(buffer: $0) }
  }
}
