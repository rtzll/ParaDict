import Foundation

enum StreamingPreviewUpdate: Sendable, Equatable {
  case reset
  case committed(String)
  case partial(String)
}

struct StreamingTranscriptAccumulator: Sendable, Equatable {
  private var committedSegments: [String] = []
  private var hypothesisText = ""

  var displayText: String {
    Self.join(committedText, hypothesisText)
  }

  @discardableResult
  mutating func apply(_ update: StreamingPreviewUpdate) -> Bool {
    let previousDisplayText = displayText

    switch update {
    case .reset:
      committedSegments = []
      hypothesisText = ""
    case .committed(let text):
      applyCommitted(text)
    case .partial(let text):
      applyPartial(text)
    }

    return displayText != previousDisplayText
  }

  private var committedText: String {
    committedSegments.joined(separator: " ")
  }

  private mutating func applyCommitted(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let previousHypothesisText = hypothesisText
    committedSegments.append(trimmed)

    let strippedFullPrefix = Self.stripCommittedPrefix(
      from: previousHypothesisText,
      committedText: committedText
    )
    if strippedFullPrefix != previousHypothesisText {
      hypothesisText = strippedFullPrefix
      return
    }

    hypothesisText = Self.stripCommittedPrefix(
      from: previousHypothesisText,
      committedText: trimmed
    )
  }

  private mutating func applyPartial(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let partialTail = Self.stripCommittedPrefix(
      from: trimmed,
      committedText: committedText
    )
    hypothesisText = partialTail
  }

  private static func join(_ prefix: String, _ tail: String) -> String {
    [prefix, tail]
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func stripCommittedPrefix(from text: String, committedText: String) -> String {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedCommitted = committedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedText.isEmpty, !trimmedCommitted.isEmpty else { return trimmedText }

    if trimmedText == trimmedCommitted { return "" }

    let exactPrefix = trimmedCommitted + " "
    if trimmedText.hasPrefix(exactPrefix) {
      return String(trimmedText.dropFirst(exactPrefix.count)).trimmingCharacters(
        in: .whitespacesAndNewlines)
    }

    return stripNormalizedWordPrefix(from: trimmedText, committedText: trimmedCommitted)
  }

  private static func stripNormalizedWordPrefix(from text: String, committedText: String) -> String
  {
    let textWords = splitWords(text)
    let committedWords = splitWords(committedText)
    guard !textWords.isEmpty, !committedWords.isEmpty else { return text }

    let compareCount = min(textWords.count, committedWords.count)
    var commonPrefixLength = 0
    for index in 0..<compareCount {
      guard normalize(textWords[index]) == normalize(committedWords[index]) else { break }
      commonPrefixLength = index + 1
    }

    if commonPrefixLength == textWords.count {
      return ""
    }

    guard commonPrefixLength == committedWords.count else { return text }

    let remainingWords = textWords.dropFirst(commonPrefixLength)
    return
      remainingWords
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func splitWords(_ text: String) -> [String] {
    text.split(whereSeparator: \.isWhitespace).map(String.init)
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
