import Foundation
import Observation
import os.log

actor RecordingFileStore: Sendable {
  private let fileManager = FileManager.default
  private let logger = Logger(subsystem: Logger.subsystem, category: "RecordingStore")

  /// Persistence failure policy:
  /// - Missing recording directories on first launch are recoverable and recreated.
  /// - Corrupt per-recording metadata is logged and skipped so one bad item does not hide history.
  /// - Explicit saves/deletes throw so callers can downgrade or surface the operation failure.
  /// - Retention cleanup is best-effort: failures are logged but do not block recording flow.
  init() {
    do {
      try fileManager.createDirectory(
        at: Recording.baseDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      logger.error("Failed to create recording directory: \(error.localizedDescription)")
    }
  }

  func saveWithExistingAudio(_ recording: Recording) throws {
    guard fileManager.fileExists(atPath: recording.audioURL.path) else {
      throw NSError(
        domain: "RecordingStore",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Audio file does not exist"]
      )
    }

    try saveMetadata(recording)
    try saveTranscriptionFiles(recording)
  }

  func saveFailedRecording(_ recording: Recording) throws {
    try saveMetadata(recording)
  }

  func delete(_ recording: Recording) throws {
    guard fileManager.fileExists(atPath: recording.storageDirectory.path) else { return }
    try fileManager.removeItem(at: recording.storageDirectory)
  }

  func loadAll() throws -> [Recording] {
    try ensureDirectoryExists()

    let baseDir = Recording.baseDirectory
    let contents: [String]
    do {
      contents = try fileManager.contentsOfDirectory(atPath: baseDir.path)
    } catch {
      logger.error("Failed to list recordings directory: \(error.localizedDescription)")
      throw error
    }

    var loaded: [Recording] = []
    for id in contents {
      let metadataURL = baseDir.appendingPathComponent(id).appendingPathComponent("metadata.json")
      do {
        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let recording = try decoder.decode(Recording.self, from: data)
        loaded.append(recording)
      } catch {
        logger.warning(
          "Skipping unreadable recording metadata for \(id, privacy: .public): \(error.localizedDescription)"
        )
        continue
      }
    }

    return loaded.sorted { $0.createdAt > $1.createdAt }
  }

  func removeAudioFile(at url: URL) {
    guard fileManager.fileExists(atPath: url.path) else { return }
    do {
      try fileManager.removeItem(at: url)
    } catch {
      logger.warning(
        "Failed to remove retained audio file at \(url.path, privacy: .public): \(error.localizedDescription)"
      )
    }
  }

  func discardCapture(at audioURL: URL) {
    let directory = audioURL.deletingLastPathComponent()
    guard fileManager.fileExists(atPath: directory.path) else { return }
    do {
      try fileManager.removeItem(at: directory)
    } catch {
      logger.warning(
        "Failed to discard capture at \(directory.path, privacy: .public): \(error.localizedDescription)"
      )
    }
  }

  private func ensureDirectoryExists() throws {
    do {
      try fileManager.createDirectory(
        at: Recording.baseDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      logger.error("Failed to create recording directory: \(error.localizedDescription)")
      throw error
    }
  }

  private func saveTranscriptionFiles(_ recording: Recording) throws {
    let dir = recording.storageDirectory
    if let transcript = recording.transcription?.text {
      let transcriptURL = dir.appendingPathComponent("transcript.txt")
      try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
    }
    if let segments = recording.transcription?.segments, !segments.isEmpty {
      try saveSegments(segments, totalDuration: recording.recording.duration, to: dir)
    }
  }

  private func saveMetadata(_ recording: Recording) throws {
    let dir = recording.storageDirectory
    try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

    let metadataURL = dir.appendingPathComponent("metadata.json")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(recording)
    try data.write(to: metadataURL)
  }

  private func saveSegments(
    _ segments: [TranscriptionSegment],
    totalDuration: TimeInterval,
    to dir: URL
  ) throws {
    let result = SegmentsResult(
      segments: segments,
      totalDuration: totalDuration,
      wordTimestampsEnabled: segments.contains { $0.words?.isEmpty == false }
    )
    let segmentsURL = dir.appendingPathComponent("segments.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(result)
    try data.write(to: segmentsURL)
  }
}

@Observable
@MainActor
final class RecordingHistory: Sendable {
  private(set) var recordings: [Recording]

  private let fileStore: RecordingFileStore
  private let wavRetentionInterval: TimeInterval = 15 * 60  // 15 minutes

  init(
    fileStore: RecordingFileStore = RecordingFileStore(),
    initialRecordings: [Recording] = []
  ) {
    self.fileStore = fileStore
    self.recordings = initialRecordings
  }

  // MARK: - CRUD

  func saveWithExistingAudio(_ recording: Recording) async throws {
    try await fileStore.saveWithExistingAudio(recording)
    recordings.removeAll { $0.id == recording.id }
    recordings.insert(recording, at: 0)
    await performRetention()
  }

  func saveFailedRecording(_ recording: Recording) async throws {
    try await fileStore.saveFailedRecording(recording)
    recordings.removeAll { $0.id == recording.id }
    recordings.insert(recording, at: 0)
    await performRetention()
  }

  func delete(_ recording: Recording) async throws {
    try await fileStore.delete(recording)
    recordings.removeAll { $0.id == recording.id }
  }

  func discardCapture(at audioURL: URL) async {
    await fileStore.discardCapture(at: audioURL)
  }

  // MARK: - Loading

  func loadAll() async throws {
    recordings = try await fileStore.loadAll()
  }

  // MARK: - Query

  var recentRecordings: [Recording] {
    Array(recordings.prefix(3))
  }

  var recentHistoryItems: [Recording] {
    let filtered = recordings.filter { $0.transcription != nil }
    return Array(filtered.prefix(3))
  }

  var statistics: RecordingStatistics {
    RecordingStatistics(recordings: recordings)
  }

  // MARK: - Retention

  func performRetention() async {
    let cutoff = Date().addingTimeInterval(-wavRetentionInterval)
    for recording in recordings where recording.createdAt < cutoff && recording.hasAudioFile {
      await fileStore.removeAudioFile(at: recording.audioURL)
    }
  }
}

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
