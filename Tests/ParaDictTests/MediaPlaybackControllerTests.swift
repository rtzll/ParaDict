import XCTest

@testable import ParaDict

final class FakeMediaRemote: MediaRemoteClient, @unchecked Sendable {
  var audioActive: Bool = false
  var systemAudioMuted: Bool = false
  var pauseShouldSucceed: Bool = true
  var playShouldSucceed: Bool = true
  var muteShouldSucceed: Bool = true
  var eventLog: TestEventLog?
  private(set) var pauseCount = 0
  private(set) var playCount = 0
  private(set) var muteRequests: [Bool] = []

  func isSystemAudioActive() -> Bool { audioActive }
  func sendPause() -> Bool {
    eventLog?.append("pause-media")
    pauseCount += 1
    return pauseShouldSucceed
  }
  func sendPlay() -> Bool {
    eventLog?.append("play-media")
    playCount += 1
    return playShouldSucceed
  }
  func isSystemAudioMuted() -> Bool? { systemAudioMuted }
  func setSystemAudioMuted(_ muted: Bool) -> Bool {
    muteRequests.append(muted)
    guard muteShouldSucceed else { return false }
    systemAudioMuted = muted
    return true
  }
}

private actor TestSleepRecorder {
  private var storedDurations: [Duration] = []

  func record(_ duration: Duration) {
    storedDurations.append(duration)
  }

  func durations() -> [Duration] {
    storedDurations
  }
}

@MainActor
final class MediaPlaybackControllerTests: XCTestCase {
  func test_restoreDoesNotAddArtificialDelay() async {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    let sleeps = TestSleepRecorder()
    let timing = MediaPlaybackTiming(
      muteFallbackDelay: .zero
    )
    let controller = MediaPlaybackController(
      client: fake,
      timing: timing,
      sleep: { duration in await sleeps.record(duration) }
    )
    controller.prepareForRecording()
    fake.audioActive = false

    await controller.restoreAfterRecording()

    let recordedDurations = await sleeps.durations()
    XCTAssertFalse(recordedDurations.contains(.seconds(1)))
    XCTAssertEqual(fake.playCount, 1)
  }

  func test_successfulPauseDoesNotMuteAfterPlaybackBecomesInactive() async {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    let controller = MediaPlaybackController(client: fake, timing: .immediate)

    controller.prepareForRecording()
    fake.audioActive = false
    await settleAudioActions()

    XCTAssertTrue(fake.muteRequests.isEmpty)
  }

  func test_mutesSystemAudioWhenPlaybackRemainsActiveAfterPauseAttempt() async {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    fake.pauseShouldSucceed = false
    let controller = MediaPlaybackController(client: fake, timing: .immediate)

    controller.prepareForRecording()
    await settleAudioActions()

    XCTAssertEqual(fake.muteRequests, [true])
    XCTAssertTrue(fake.systemAudioMuted)
  }

  func test_restoreUnmutesAudioMutedByTheFallback() async {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    fake.pauseShouldSucceed = false
    let controller = MediaPlaybackController(client: fake, timing: .immediate)
    controller.prepareForRecording()
    await settleAudioActions()

    await controller.restoreAfterRecording()

    XCTAssertEqual(fake.muteRequests, [true, false])
    XCTAssertFalse(fake.systemAudioMuted)
  }

  func test_restorePreservesAudioThatWasMutedBeforeRecording() async {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    fake.systemAudioMuted = true
    fake.pauseShouldSucceed = false
    let controller = MediaPlaybackController(client: fake, timing: .immediate)
    controller.prepareForRecording()
    await settleAudioActions()

    await controller.restoreAfterRecording()

    XCTAssertTrue(fake.muteRequests.isEmpty)
    XCTAssertTrue(fake.systemAudioMuted)
  }

  func test_prepareWhenAudioActive_sendsPauseAndMarksWasPlaying() async {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    let controller = MediaPlaybackController(client: fake)

    controller.prepareForRecording()

    XCTAssertEqual(fake.pauseCount, 1)
    fake.audioActive = false
    await controller.restoreAfterRecording()
    XCTAssertEqual(fake.playCount, 1, "resume should fire because we paused active audio")
  }

  func test_prepareWhenPauseCommandFails_doesNotArmResume() async {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    fake.pauseShouldSucceed = false
    let controller = MediaPlaybackController(client: fake)

    controller.prepareForRecording()
    await controller.restoreAfterRecording()

    XCTAssertEqual(fake.pauseCount, 1)
    XCTAssertEqual(fake.playCount, 0, "resume must not fire when pause was not accepted")
  }

  func test_prepareWhenNoAudio_doesNotSendPause_andDoesNotResumeLater() async {
    let fake = FakeMediaRemote()
    fake.audioActive = false
    let controller = MediaPlaybackController(client: fake)

    controller.prepareForRecording()

    XCTAssertEqual(fake.pauseCount, 0)
    await controller.restoreAfterRecording()
    XCTAssertEqual(fake.playCount, 0, "resume must not fire when we never paused anything")
  }

  func test_prepareWhenUserAlreadyPaused_doesNotResumeOnStop() async {
    // User paused their video before dictating; system audio is idle.
    let fake = FakeMediaRemote()
    fake.audioActive = false
    let controller = MediaPlaybackController(client: fake)

    controller.prepareForRecording()
    await controller.restoreAfterRecording()

    XCTAssertEqual(fake.pauseCount, 0)
    XCTAssertEqual(fake.playCount, 0)
  }

  func test_restoreWithoutPreparationFirst_isNoop() async {
    let fake = FakeMediaRemote()
    let controller = MediaPlaybackController(client: fake)

    await controller.restoreAfterRecording()

    XCTAssertEqual(fake.playCount, 0)
  }

  func test_restoreOnlyFiresOnce() async {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    let controller = MediaPlaybackController(client: fake)

    controller.prepareForRecording()
    fake.audioActive = false
    await controller.restoreAfterRecording()
    await controller.restoreAfterRecording()

    XCTAssertEqual(fake.playCount, 1)
  }

  func test_restoreSendsPlayWhenOutputRemainsActive() async {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    let controller = MediaPlaybackController(client: fake)

    controller.prepareForRecording()
    fake.audioActive = true
    await controller.restoreAfterRecording()

    XCTAssertEqual(fake.pauseCount, 1)
    XCTAssertEqual(
      fake.playCount,
      1,
      "device-level activity does not prove that the media we paused has resumed"
    )
  }

  private func settleAudioActions() async {
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(10))
    await Task.yield()
  }
}
