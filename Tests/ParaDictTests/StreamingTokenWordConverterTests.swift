@preconcurrency import FluidAudio
import Testing

@testable import ParaDict

struct StreamingTokenWordConverterTests {
  @Test func mergesWordPieceTokensIntoOffsetWords() {
    let timings = [
      TokenTiming(token: "▁Hello", tokenId: 1, startTime: 0.0, endTime: 0.2, confidence: 0.8),
      TokenTiming(token: "!", tokenId: 2, startTime: 0.2, endTime: 0.3, confidence: 0.6),
      TokenTiming(token: " world", tokenId: 3, startTime: 0.4, endTime: 0.7, confidence: 0.9),
    ]

    let words = StreamingTokenWordConverter().words(from: timings, timeOffset: 1.0)

    #expect(words.map(\.text) == ["Hello!", "world"])
    #expect(words[0].startTime == 1.0)
    #expect(words[0].endTime == 1.3)
    #expect(abs(words[0].confidence - 0.7) < 0.0001)
    #expect(words[1].startTime == 1.4)
    #expect(words[1].endTime == 1.7)
    #expect(words[1].confidence == 0.9)
  }

  @Test func initialTokenWithoutWordPrefixStillCreatesWord() {
    let timings = [
      TokenTiming(token: "Hel", tokenId: 1, startTime: 0.1, endTime: 0.2, confidence: 0.8),
      TokenTiming(token: "lo", tokenId: 2, startTime: 0.2, endTime: 0.3, confidence: 1.0),
    ]

    let words = StreamingTokenWordConverter().words(from: timings, timeOffset: 0)

    #expect(words.map(\.text) == ["Hello"])
    #expect(words[0].startTime == 0.1)
    #expect(words[0].endTime == 0.3)
    #expect(abs(words[0].confidence - 0.9) < 0.0001)
  }
}
