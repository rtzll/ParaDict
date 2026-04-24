import Testing

@testable import ParaDict

struct StreamingTranscriptAccumulatorTests {
  @Test func emptyPartialDoesNotClearVisibleTranscript() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.partial("hello world"))

    let didChange = accumulator.apply(.partial(""))

    #expect(!didChange)
    #expect(accumulator.displayText == "hello world")
  }

  @Test func partialReplacesPreviousHypothesis() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.partial("The first sentence. The second sentence."))

    let didChange = accumulator.apply(.partial("The first sentence."))

    #expect(didChange)
    #expect(accumulator.displayText == "The first sentence.")
  }

  @Test func committedTextIsPreservedWhenPartialIsTailOnly() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.committed("The first sentence."))

    accumulator.apply(.partial("The second sentence."))

    #expect(accumulator.displayText == "The first sentence. The second sentence.")
  }

  @Test func sameLengthPartialCanRewriteHypothesis() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.partial("The first sentence."))

    let didChange = accumulator.apply(.partial("A revised sentence."))

    #expect(didChange)
    #expect(accumulator.displayText == "A revised sentence.")
  }

  @Test func cumulativePartialDoesNotDuplicateCommittedPrefix() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.committed("The first sentence."))

    accumulator.apply(.partial("The first sentence. The second sentence."))

    #expect(accumulator.displayText == "The first sentence. The second sentence.")
  }

  @Test func punctuationDifferencesDoNotDuplicateCommittedPrefix() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.committed("Hello, world."))

    accumulator.apply(.partial("hello world this is the tail"))

    #expect(accumulator.displayText == "Hello, world. this is the tail")
  }

  @Test func stalePartialCoveredByCommittedTextIsIgnored() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.committed("The first sentence. The second sentence."))

    let didChange = accumulator.apply(.partial("The first sentence."))

    #expect(!didChange)
    #expect(accumulator.displayText == "The first sentence. The second sentence.")
  }

  @Test func shorterTailOnlyPartialPreservesCommittedText() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.committed("The first sentence."))
    accumulator.apply(.partial("The second sentence. The third sentence."))

    let didChange = accumulator.apply(.partial("The second sentence."))

    #expect(didChange)
    #expect(accumulator.displayText == "The first sentence. The second sentence.")
  }

  @Test func repeatedCommittedSegmentsArePreserved() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.committed("This phrase repeats."))

    accumulator.apply(.committed("This phrase repeats."))

    #expect(accumulator.displayText == "This phrase repeats. This phrase repeats.")
  }

  @Test func committedUpdateKeepsExistingHypothesisTail() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.partial("The first sentence. The second sentence."))

    accumulator.apply(.committed("The first sentence."))

    #expect(accumulator.displayText == "The first sentence. The second sentence.")
  }

  @Test func committedUpdateStripsNewlyCommittedTextFromTailOnlyHypothesis() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.committed("The first sentence."))
    accumulator.apply(.partial("The second sentence. The third sentence."))

    accumulator.apply(.committed("The second sentence."))

    #expect(
      accumulator.displayText
        == "The first sentence. The second sentence. The third sentence.")
  }

  @Test func resetClearsCommittedAndHypothesisText() {
    var accumulator = StreamingTranscriptAccumulator()
    accumulator.apply(.committed("The first sentence."))
    accumulator.apply(.partial("The second sentence."))

    accumulator.apply(.reset)

    #expect(accumulator.displayText.isEmpty)
  }
}
