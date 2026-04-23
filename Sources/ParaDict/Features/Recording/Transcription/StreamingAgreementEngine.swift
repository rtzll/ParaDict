import Foundation

struct StreamingWord: Sendable {
  let text: String
  let normalizedText: String
  let startTime: Double
  let endTime: Double
  let confidence: Float

  init(text: String, startTime: Double, endTime: Double, confidence: Float) {
    self.text = text
    self.normalizedText = Self.normalize(text)
    self.startTime = startTime
    self.endTime = endTime
    self.confidence = confidence
  }

  private static func normalize(_ text: String) -> String {
    String(
      text.lowercased()
        .replacingOccurrences(of: "-", with: " ")
        .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct StreamingAgreementResult: Sendable {
  let fullText: String
}

struct StreamingAgreementConfig: Sendable {
  var transcribeIntervalSeconds: Double = 0.8
  var confirmationsNeeded: Int = 2
  var minWordsToConfirm: Int = 3
  var minPassConfidence: Float = 0.12
  var minBoundaryConfidence: Float = 0.45
}

/// Local-agreement decoder: accumulates transcription passes and promotes a
/// prefix to "confirmed" once successive passes agree on it. Everything after
/// the confirmed prefix is treated as a fluid hypothesis that can still change.
/// Safe to share across isolation boundaries because it is stored as a `var`
/// property inside `ParakeetStreamingSession` (an actor), which serializes all
/// access. As a struct with only Sendable stored properties, it conforms to
/// `Sendable` automatically.
struct StreamingAgreementEngine: Sendable {
  private var config: StreamingAgreementConfig

  private var confirmedWords: [StreamingWord] = []
  private var previousWords: [StreamingWord] = []
  private var consecutiveAgreementCount = 0
  private var isFirstPass = true

  private(set) var confirmedEndTime: Double = 0
  private(set) var hypothesisStartTime: Double = 0

  init(config: StreamingAgreementConfig = StreamingAgreementConfig()) {
    self.config = config
  }

  mutating func reset() {
    confirmedWords = []
    previousWords = []
    consecutiveAgreementCount = 0
    isFirstPass = true
    confirmedEndTime = 0
    hypothesisStartTime = 0
  }

  mutating func process(words: [StreamingWord], confidence: Float) -> StreamingAgreementResult {
    guard !words.isEmpty else {
      return makeResult(hypothesisWords: [])
    }

    if isFirstPass {
      isFirstPass = false
      previousWords = words
      hypothesisStartTime = words.first?.startTime ?? 0
      return makeResult(hypothesisWords: words)
    }

    if confidence < config.minPassConfidence {
      consecutiveAgreementCount = 0
      previousWords = words
      hypothesisStartTime = words.first?.startTime ?? confirmedEndTime
      return makeResult(hypothesisWords: words)
    }

    let prefix = commonPrefix(current: words, previous: previousWords)
    previousWords = words

    if prefix.count >= config.minWordsToConfirm {
      consecutiveAgreementCount += 1
    } else {
      consecutiveAgreementCount = 0
      hypothesisStartTime = words.first?.startTime ?? confirmedEndTime
      return makeResult(hypothesisWords: words)
    }

    guard consecutiveAgreementCount >= config.confirmationsNeeded else {
      hypothesisStartTime = words.first?.startTime ?? confirmedEndTime
      return makeResult(hypothesisWords: words)
    }

    let confirmCount = confirmationBoundary(in: Array(words.prefix(prefix.count)))
    guard confirmCount > 0 else {
      hypothesisStartTime = words.first?.startTime ?? confirmedEndTime
      return makeResult(hypothesisWords: words)
    }

    let boundaryWords = Array(words.prefix(confirmCount).suffix(2))
    let minConfidence = boundaryWords.map(\.confidence).min() ?? 1
    guard minConfidence >= config.minBoundaryConfidence else {
      hypothesisStartTime = words.first?.startTime ?? confirmedEndTime
      return makeResult(hypothesisWords: words)
    }

    let newlyConfirmed = Array(words.prefix(confirmCount))
    let hypothesis = Array(words.dropFirst(confirmCount))

    confirmedWords.append(contentsOf: newlyConfirmed)
    confirmedEndTime = newlyConfirmed.last?.endTime ?? confirmedEndTime
    hypothesisStartTime = hypothesis.first?.startTime ?? confirmedEndTime

    consecutiveAgreementCount = hypothesis.isEmpty ? 0 : 1
    previousWords = hypothesis
    isFirstPass = hypothesis.isEmpty

    return makeResult(hypothesisWords: hypothesis)
  }

  private func commonPrefix(current: [StreamingWord], previous: [StreamingWord]) -> [StreamingWord]
  {
    let count = min(current.count, previous.count)
    var prefixLength = 0

    for index in 0..<count {
      if current[index].normalizedText == previous[index].normalizedText {
        prefixLength = index + 1
      } else {
        break
      }
    }

    return Array(current.prefix(prefixLength))
  }

  private func confirmationBoundary(in words: [StreamingWord]) -> Int {
    guard words.count >= config.minWordsToConfirm else { return 0 }

    let sentenceEnders: Set<Character> = [".", "!", "?", ";", ","]
    for index in stride(from: words.count - 1, through: 0, by: -1) {
      if let last = words[index].text.last, sentenceEnders.contains(last) {
        return index + 1
      }
    }

    return max(0, words.count - 2)
  }

  private func makeResult(hypothesisWords: [StreamingWord]) -> StreamingAgreementResult {
    var parts: [String] = []
    let confirmed = confirmedWords.map(\.text).joined(separator: " ")
    let hypothesis = hypothesisWords.map(\.text).joined(separator: " ")

    if !confirmed.isEmpty {
      parts.append(confirmed)
    }
    if !hypothesis.isEmpty {
      parts.append(hypothesis)
    }

    return StreamingAgreementResult(
      fullText: parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines))
  }
}
