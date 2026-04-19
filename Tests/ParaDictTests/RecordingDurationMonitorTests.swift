import Foundation
import Testing

@testable import ParaDict

@MainActor
struct RecordingDurationMonitorTests {
  @Test func emitsWarningOnlyOnceAfterThreshold() {
    var currentDuration: TimeInterval = 0
    var warningShown = false
    var warningCalls: [Int] = []
    var stopCalls = 0

    let monitor = RecordingDurationMonitor(
      maximumDuration: 600,
      warningDuration: 480,
      currentDuration: { currentDuration },
      hasShownWarning: { warningShown },
      markWarningShown: { warningShown = true },
      onWarning: { warningCalls.append($0) },
      onLimitReached: { stopCalls += 1 }
    )

    currentDuration = 479
    monitor.evaluateCurrentDuration()
    #expect(warningCalls.isEmpty)
    #expect(!warningShown)
    #expect(stopCalls == 0)

    currentDuration = 481
    monitor.evaluateCurrentDuration()
    #expect(warningShown)
    #expect(warningCalls == [119])
    #expect(stopCalls == 0)

    currentDuration = 500
    monitor.evaluateCurrentDuration()
    #expect(warningCalls == [119])
    #expect(stopCalls == 0)
  }

  @Test func autoStopFiresAtMaximumDuration() {
    let currentDuration: TimeInterval = 600
    var warningShown = false
    var warningCalls: [Int] = []
    var stopCalls = 0

    let monitor = RecordingDurationMonitor(
      maximumDuration: 600,
      warningDuration: 480,
      currentDuration: { currentDuration },
      hasShownWarning: { warningShown },
      markWarningShown: { warningShown = true },
      onWarning: { warningCalls.append($0) },
      onLimitReached: { stopCalls += 1 }
    )

    monitor.evaluateCurrentDuration()

    #expect(warningShown)
    #expect(warningCalls == [0])
    #expect(stopCalls == 1)
  }
}
