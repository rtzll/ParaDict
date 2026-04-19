import Foundation
import Observation
import os.log

actor AnalyticsFileStore: Sendable {
  private let fileURL: URL
  private let fileManager = FileManager.default
  private let logger = Logger(subsystem: Logger.subsystem, category: "AnalyticsStore")

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  func load() -> AnalyticsStore.Totals? {
    ensureParentDirectoryExists()

    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }

    do {
      return try JSONDecoder().decode(AnalyticsStore.Totals.self, from: data)
    } catch {
      logger.error("Failed to decode analytics store: \(error.localizedDescription)")
      return nil
    }
  }

  func save(_ totals: AnalyticsStore.Totals) {
    ensureParentDirectoryExists()

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    do {
      let data = try encoder.encode(totals)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      logger.error("Failed to save analytics store: \(error.localizedDescription)")
    }
  }

  private func ensureParentDirectoryExists() {
    let directoryURL = fileURL.deletingLastPathComponent()
    do {
      try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    } catch {
      logger.error("Failed to create analytics directory: \(error.localizedDescription)")
    }
  }
}

@Observable
@MainActor
final class AnalyticsStore: Sendable {
  private(set) var totals = Totals()
  private let fileStore: AnalyticsFileStore

  private static var defaultFileURL: URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return docs.appendingPathComponent("ParaDict/analytics.json")
  }

  struct Totals: Codable, Equatable, Sendable {
    var totalRecordings: Int = 0
    var totalDuration: TimeInterval = 0
    var totalWords: Int = 0
  }

  init(
    fileURL: URL = AnalyticsStore.defaultFileURL
  ) {
    fileStore = AnalyticsFileStore(fileURL: fileURL)
  }

  // MARK: - Computed

  var formattedSpeakingTime: String {
    Self.formatDuration(Int(totals.totalDuration))
  }

  var averageWPM: Int {
    Self.calculateWPM(totalWords: totals.totalWords, totalDuration: totals.totalDuration)
  }

  nonisolated static func formatDuration(_ totalSeconds: Int) -> String {
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

  nonisolated static func calculateWPM(totalWords: Int, totalDuration: TimeInterval) -> Int {
    guard totalDuration >= 60 else { return 0 }
    return Int(Double(totalWords) / (totalDuration / 60))
  }

  var formattedRecordings: String {
    Self.compactNumber(totals.totalRecordings)
  }

  var formattedWords: String {
    Self.compactNumber(totals.totalWords)
  }

  nonisolated static func compactNumber(_ value: Int) -> String {
    switch value {
    case ..<1_000:
      return "\(value)"
    case ..<1_000_000:
      let k = Double(value) / 1_000
      return k >= 10 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
    default:
      let m = Double(value) / 1_000_000
      return m >= 10 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
    }
  }

  // MARK: - Persistence

  @discardableResult
  func load() async -> Bool {
    guard let totals = await fileStore.load() else {
      return false
    }
    self.totals = totals
    return true
  }

  func seedFromRecordings(_ recordings: [Recording]) async {
    var nextTotals = Totals()

    for recording in recordings {
      guard recording.recording.duration >= 1.0,
        let transcription = recording.transcription
      else { continue }

      nextTotals.totalRecordings += 1
      nextTotals.totalDuration += recording.recording.duration
      nextTotals.totalWords += transcription.text.split(separator: " ").count
    }

    totals = nextTotals
    await fileStore.save(totals)
  }

  func record(duration: TimeInterval, wordCount: Int) async {
    totals.totalRecordings += 1
    totals.totalDuration += duration
    totals.totalWords += wordCount
    await fileStore.save(totals)
  }
}
