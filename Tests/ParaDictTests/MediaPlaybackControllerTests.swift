import XCTest

@testable import ParaDict

final class FakeMediaRemote: MediaRemoteClient, @unchecked Sendable {
  var audioActive: Bool = false
  var pauseShouldSucceed: Bool = true
  var playShouldSucceed: Bool = true
  private(set) var pauseCount = 0
  private(set) var playCount = 0

  func isSystemAudioActive() -> Bool { audioActive }
  func sendPause() -> Bool {
    pauseCount += 1
    return pauseShouldSucceed
  }
  func sendPlay() -> Bool {
    playCount += 1
    return playShouldSucceed
  }
}

@MainActor
final class MediaPlaybackControllerTests: XCTestCase {
  func test_pauseWhenAudioActive_sendsPauseAndMarksWasPlaying() {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    let controller = MediaPlaybackController(client: fake)

    controller.pauseMedia()

    XCTAssertEqual(fake.pauseCount, 1)
    fake.audioActive = false
    controller.resumeIfPaused()
    XCTAssertEqual(fake.playCount, 1, "resume should fire because we paused active audio")
  }

  func test_pauseWhenPauseCommandFails_doesNotArmResume() {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    fake.pauseShouldSucceed = false
    let controller = MediaPlaybackController(client: fake)

    controller.pauseMedia()
    controller.resumeIfPaused()

    XCTAssertEqual(fake.pauseCount, 1)
    XCTAssertEqual(fake.playCount, 0, "resume must not fire when pause was not accepted")
  }

  func test_pauseWhenNoAudio_doesNotSendPause_andDoesNotResumeLater() {
    let fake = FakeMediaRemote()
    fake.audioActive = false
    let controller = MediaPlaybackController(client: fake)

    controller.pauseMedia()

    XCTAssertEqual(fake.pauseCount, 0)
    controller.resumeIfPaused()
    XCTAssertEqual(fake.playCount, 0, "resume must not fire when we never paused anything")
  }

  func test_pauseWhenUserAlreadyPaused_doesNotResumeOnStop() {
    // User paused their video before dictating; system audio is idle.
    let fake = FakeMediaRemote()
    fake.audioActive = false
    let controller = MediaPlaybackController(client: fake)

    controller.pauseMedia()
    controller.resumeIfPaused()

    XCTAssertEqual(fake.pauseCount, 0)
    XCTAssertEqual(fake.playCount, 0)
  }

  func test_resumeWithoutPauseFirst_isNoop() {
    let fake = FakeMediaRemote()
    let controller = MediaPlaybackController(client: fake)

    controller.resumeIfPaused()

    XCTAssertEqual(fake.playCount, 0)
  }

  func test_resumeOnlyFiresOnce() {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    let controller = MediaPlaybackController(client: fake)

    controller.pauseMedia()
    fake.audioActive = false
    controller.resumeIfPaused()
    controller.resumeIfPaused()

    XCTAssertEqual(fake.playCount, 1)
  }

  func test_resumeSkipsWhenAudioIsAlreadyActiveAgain() {
    let fake = FakeMediaRemote()
    fake.audioActive = true
    let controller = MediaPlaybackController(client: fake)

    controller.pauseMedia()
    fake.audioActive = true
    controller.resumeIfPaused()

    XCTAssertEqual(fake.pauseCount, 1)
    XCTAssertEqual(fake.playCount, 0, "resume must not fire if audio is already active again")
  }
}
