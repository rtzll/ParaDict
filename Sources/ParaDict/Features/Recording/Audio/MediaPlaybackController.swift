import CoreAudio
import Foundation
import os.log

protocol MediaRemoteClient: Sendable {
  func isSystemAudioActive() -> Bool
  func sendPause() -> Bool
  func sendPlay() -> Bool
}

// Detection uses CoreAudio (public API, works from signed apps).
// Commands use MediaRemote.framework via dlopen (send commands work from signed apps,
// only queries are blocked).
final class MediaRemoteFramework: MediaRemoteClient, @unchecked Sendable {
  nonisolated(unsafe) private static let handle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)

  private typealias SendCmdFn = @convention(c) (Int32, AnyObject?) -> Bool

  private static let sendCommand: SendCmdFn? = {
    guard let h = handle, let sym = dlsym(h, "MRMediaRemoteSendCommand") else { return nil }
    return unsafeBitCast(sym, to: SendCmdFn.self)
  }()

  func isSystemAudioActive() -> Bool {
    guard let deviceID = Self.defaultOutputDeviceID() else { return false }
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
    return status == noErr && running != 0
  }

  func sendPause() -> Bool { Self.sendCommand?(1, nil) ?? false }
  func sendPlay() -> Bool { Self.sendCommand?(0, nil) ?? false }

  private static func defaultOutputDeviceID() -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceID: AudioObjectID = 0
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
    return status == noErr ? deviceID : nil
  }
}

@MainActor
final class MediaPlaybackController {
  private let log = Logger(subsystem: Logger.subsystem, category: "MediaPlayback")
  private let client: MediaRemoteClient
  private var resumePending = false

  init(client: MediaRemoteClient = MediaRemoteFramework()) {
    self.client = client
  }

  func pauseMedia() {
    resumePending = false
    guard client.isSystemAudioActive() else {
      log.info("pauseMedia: no system audio, skipping")
      return
    }

    guard client.sendPause() else {
      log.info("pauseMedia: pause command was not accepted")
      return
    }

    resumePending = true
    log.info("pauseMedia: paused and armed resume")
  }

  func resumeIfPaused() {
    guard resumePending else {
      log.info("resumeIfPaused: resumePending=false, skipping")
      return
    }

    defer { resumePending = false }

    guard !client.isSystemAudioActive() else {
      log.info("resumeIfPaused: audio already active again, skipping auto-resume")
      return
    }

    guard client.sendPlay() else {
      log.info("resumeIfPaused: play command was not accepted")
      return
    }

    log.info("resumeIfPaused: resumed")
  }
}
