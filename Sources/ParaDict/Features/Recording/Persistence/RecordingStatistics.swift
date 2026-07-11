import Foundation

struct RecordingStatistics: Equatable, Sendable {
  let totalRecordings: Int
  let totalDuration: TimeInterval
  let totalWords: Int

  init(recordings: [Recording]) {
    let completed = recordings.filter {
      $0.status == .completed
        && $0.recording.duration >= 1
        && $0.transcription != nil
    }
    totalRecordings = completed.count
    totalDuration = completed.reduce(0) { $0 + $1.recording.duration }
    totalWords = completed.reduce(0) {
      $0 + ($1.transcription?.text.split(separator: " ").count ?? 0)
    }
  }

  var formattedSpeakingTime: String {
    Self.formatDuration(Int(totalDuration))
  }

  var averageWPM: Int {
    Self.calculateWPM(totalWords: totalWords, totalDuration: totalDuration)
  }

  var formattedRecordings: String { Self.compactNumber(totalRecordings) }
  var formattedWords: String { Self.compactNumber(totalWords) }

  static func formatDuration(_ totalSeconds: Int) -> String {
    let days = totalSeconds / 86400
    let hours = (totalSeconds % 86400) / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if days > 0 {
      return "\(days)d \(hours)h"
    } else if hours > 0 {
      return "\(hours)h \(minutes)m"
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  static func calculateWPM(totalWords: Int, totalDuration: TimeInterval) -> Int {
    guard totalDuration >= 60 else { return 0 }
    return Int(Double(totalWords) / (totalDuration / 60))
  }

  static func compactNumber(_ value: Int) -> String {
    switch value {
    case ..<1_000:
      return "\(value)"
    case ..<1_000_000:
      let thousands = Double(value) / 1_000
      return thousands >= 10
        ? String(format: "%.0fK", thousands)
        : String(format: "%.1fK", thousands)
    default:
      let millions = Double(value) / 1_000_000
      return millions >= 10
        ? String(format: "%.0fM", millions)
        : String(format: "%.1fM", millions)
    }
  }
}
