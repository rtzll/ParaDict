@preconcurrency import FluidAudio
import Foundation

struct StreamingTokenWordConverter: Sendable {
  func words(from timings: [TokenTiming], timeOffset: Double) -> [StreamingWord] {
    guard !timings.isEmpty else { return [] }

    var words: [StreamingWord] = []
    var currentText = ""
    var startTime = 0.0
    var endTime = 0.0
    var confidences: [Float] = []

    for timing in timings {
      let token = timing.token
      let startsWord = token.hasPrefix("▁") || token.hasPrefix(" ")

      if startsWord {
        appendCurrentWord(
          to: &words,
          currentText: currentText,
          startTime: startTime,
          endTime: endTime,
          confidences: confidences,
          timeOffset: timeOffset
        )

        currentText = token.trimmingCharacters(in: .whitespaces).replacingOccurrences(
          of: "▁", with: "")
        startTime = timing.startTime
        endTime = timing.endTime
        confidences = [timing.confidence]
      } else {
        if currentText.isEmpty {
          startTime = timing.startTime
        }
        currentText += token
        endTime = timing.endTime
        confidences.append(timing.confidence)
      }
    }

    appendCurrentWord(
      to: &words,
      currentText: currentText,
      startTime: startTime,
      endTime: endTime,
      confidences: confidences,
      timeOffset: timeOffset
    )

    return words
  }

  private func appendCurrentWord(
    to words: inout [StreamingWord],
    currentText: String,
    startTime: Double,
    endTime: Double,
    confidences: [Float],
    timeOffset: Double
  ) {
    guard !currentText.isEmpty else { return }

    let confidence =
      confidences.isEmpty ? 1.0 : confidences.reduce(0, +) / Float(confidences.count)
    words.append(
      StreamingWord(
        text: currentText,
        startTime: startTime + timeOffset,
        endTime: endTime + timeOffset,
        confidence: confidence
      )
    )
  }
}
