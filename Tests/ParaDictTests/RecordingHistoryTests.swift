import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingHistoryTests {
  @Test func statisticsAreDerivedFromCompletedRecordings() {
    let history = RecordingHistory(
      initialRecordings: [
        makeRecording(id: "completed", duration: 120, text: "one two three"),
        makeRecording(id: "failed", duration: 20, text: nil, status: .failed),
        makeRecording(id: "too-short", duration: 0.5, text: "ignored"),
      ])

    #expect(history.statistics.totalRecordings == 1)
    #expect(history.statistics.totalDuration == 120)
    #expect(history.statistics.totalWords == 3)
    #expect(history.statistics.averageWPM == 1)
  }

  private func makeRecording(
    id: String,
    duration: TimeInterval,
    text: String?,
    status: RecordingStatus = .completed
  ) -> Recording {
    Recording(
      id: id,
      createdAt: Date(timeIntervalSince1970: 0),
      recording: RecordingInfo(
        duration: duration,
        sampleRate: 16_000,
        channels: 1,
        fileSize: 0,
        inputDevice: "Test"
      ),
      transcription: text.map {
        RecordingTranscription(
          text: $0,
          segments: [],
          language: "en",
          model: "test",
          transcriptionDuration: 0
        )
      },
      configuration: RecordingConfiguration(voiceModel: "test", language: "en"),
      status: status
    )
  }
}
