import Testing

@testable import ParaDict

struct StreamingAgreementEngineTests {
  @Test func unpunctuatedSpeechStaysHypothesisOnly() {
    var engine = StreamingAgreementEngine()
    let words = makeWords([
      "this", "is", "a", "long", "phrase", "without", "an", "ending",
    ])

    var result = engine.process(words: words, confidence: 0.9)
    result = engine.process(words: words, confidence: 0.9)
    result = engine.process(words: words, confidence: 0.9)
    result = engine.process(words: words, confidence: 0.9)

    #expect(result.newlyConfirmedText.isEmpty)
    #expect(result.fullText == "this is a long phrase without an ending")
    #expect(engine.hypothesisStartTime == 0)
  }

  @Test func failedAgreementDoesNotAdvanceUnconfirmedSeekTime() {
    var engine = StreamingAgreementEngine()
    let firstPass = makeWords(
      ["this", "is", "the", "first", "unstable", "phrase"],
      startTime: 20
    )
    let rewrittenPass = makeWords(
      ["now", "the", "decoder", "rewrote", "that", "phrase"],
      startTime: 24
    )

    _ = engine.process(words: firstPass, confidence: 0.9)
    let result = engine.process(words: rewrittenPass, confidence: 0.9)

    #expect(result.newlyConfirmedText.isEmpty)
    #expect(engine.hypothesisStartTime == 0)
    #expect(engine.confirmedEndTime == 0)
  }

  @Test func confirmsOnlyOlderSentenceAndKeepsRecentSentencesFluid() {
    var engine = StreamingAgreementEngine()
    let words = makeWords([
      "This", "is", "the", "first", "sentence.",
      "This", "is", "the", "second", "sentence.",
      "This", "is", "the", "third", "sentence.",
    ])

    _ = engine.process(words: words, confidence: 0.9)
    _ = engine.process(words: words, confidence: 0.9)
    _ = engine.process(words: words, confidence: 0.9)
    let result = engine.process(words: words, confidence: 0.9)

    #expect(result.newlyConfirmedText == "This is the first sentence.")
    #expect(
      result.fullText
        == "This is the first sentence. This is the second sentence. This is the third sentence.")
    #expect(engine.confirmedEndTime == 1.25)
    #expect(engine.hypothesisStartTime == 1.25)
  }

  @Test func unconfirmedSeekTimeStaysAtHypothesisStartAfterConfirmation() {
    var engine = StreamingAgreementEngine()
    let confirmedAndHypothesis = makeWords([
      "This", "is", "the", "first", "sentence.",
      "This", "is", "the", "second", "sentence.",
      "This", "is", "the", "third", "sentence.",
    ])

    _ = engine.process(words: confirmedAndHypothesis, confidence: 0.9)
    _ = engine.process(words: confirmedAndHypothesis, confidence: 0.9)
    _ = engine.process(words: confirmedAndHypothesis, confidence: 0.9)
    _ = engine.process(words: confirmedAndHypothesis, confidence: 0.9)

    let hypothesisStartTime = engine.hypothesisStartTime
    let laterUnstablePass = makeWords(
      ["different", "words", "from", "a", "later", "window"],
      startTime: 12
    )
    _ = engine.process(words: laterUnstablePass, confidence: 0.9)

    #expect(engine.hypothesisStartTime == hypothesisStartTime)
  }

  @Test func lowConfidencePassDoesNotAdvanceUnconfirmedSeekTime() {
    var engine = StreamingAgreementEngine()
    let words = makeWords(
      ["this", "is", "a", "low", "confidence", "phrase"],
      startTime: 15
    )

    _ = engine.process(words: words, confidence: 0.9)
    _ = engine.process(words: words, confidence: 0.1)

    #expect(engine.hypothesisStartTime == 0)
    #expect(engine.confirmedEndTime == 0)
  }

  @Test func lowConfidenceBoundaryDoesNotConfirm() {
    var engine = StreamingAgreementEngine()
    let words = makeWords(
      [
        "This", "is", "the", "first", "sentence.",
        "This", "is", "the", "second", "sentence.",
        "This", "is", "the", "third", "sentence.",
      ], boundaryConfidence: 0.4)

    _ = engine.process(words: words, confidence: 0.9)
    _ = engine.process(words: words, confidence: 0.9)
    _ = engine.process(words: words, confidence: 0.9)
    let result = engine.process(words: words, confidence: 0.9)

    #expect(result.newlyConfirmedText.isEmpty)
  }

  private func makeWords(
    _ texts: [String],
    startTime: Double = 0,
    boundaryConfidence: Float = 0.9
  ) -> [StreamingWord] {
    texts.enumerated().map { index, text in
      let confidence = text.hasSuffix(".") ? boundaryConfidence : Float(0.9)
      return StreamingWord(
        text: text,
        startTime: startTime + Double(index) * 0.25,
        endTime: startTime + Double(index + 1) * 0.25,
        confidence: confidence
      )
    }
  }
}
