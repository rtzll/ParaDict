import Testing

@testable import ParaDict

struct StreamingTranscriptionWindowTests {
  @Test func longUnconfirmedWindowIsNotSuffixCapped() throws {
    let samples = (0..<300).map(Float.init)

    let window = try #require(
      StreamingTranscriptionWindow.make(
        audioBuffer: samples,
        trimmedSampleCount: 1_000,
        bufferRelativeSeek: 20,
        inputSampleRate: 10,
        trailingSilenceSeconds: 1,
        maxSinglePassSeconds: 15
      ))

    #expect(window.samples.count == 280)
    #expect(window.samples.first == 20)
    #expect(window.samples.last == 299)
    #expect(window.timeOffset == 102)
  }

  @Test func shortWindowAddsTrailingSilenceForPunctuationCapture() throws {
    let samples = (0..<100).map(Float.init)

    let window = try #require(
      StreamingTranscriptionWindow.make(
        audioBuffer: samples,
        trimmedSampleCount: 40,
        bufferRelativeSeek: 20,
        inputSampleRate: 10,
        trailingSilenceSeconds: 1,
        maxSinglePassSeconds: 15
      ))

    #expect(window.samples.count == 90)
    #expect(Array(window.samples.prefix(3)) == [20, 21, 22])
    #expect(Array(window.samples.suffix(10)) == Array(repeating: Float(0), count: 10))
    #expect(window.timeOffset == 6)
  }

  @Test func windowReturnsNilUntilAtLeastOneSecondIsAvailable() {
    let samples = (0..<9).map(Float.init)

    let window = StreamingTranscriptionWindow.make(
      audioBuffer: samples,
      trimmedSampleCount: 0,
      bufferRelativeSeek: 0,
      inputSampleRate: 10,
      trailingSilenceSeconds: 1
    )

    #expect(window == nil)
  }
}
