import CoreAudio
import Foundation
import os.log

protocol MediaRemoteClient: Sendable {
  func isSystemAudioActive() -> Bool
  func sendPause() -> Bool
  func sendPlay() -> Bool
  func isSystemAudioMuted() -> Bool?
  func setSystemAudioMuted(_ muted: Bool) -> Bool
  func isBluetoothInputDevice(_ deviceID: AudioDeviceID) -> Bool
}

struct MediaPlaybackTiming: Sendable {
  let muteFallbackDelay: Duration
  let bluetoothRestorationDelay: Duration

  static let live = MediaPlaybackTiming(
    muteFallbackDelay: .milliseconds(220),
    bluetoothRestorationDelay: .seconds(1)
  )
  static let immediate = MediaPlaybackTiming(
    muteFallbackDelay: .zero,
    bluetoothRestorationDelay: .zero
  )
}

// Detection uses CoreAudio (public API, works from signed apps).
// Commands use MediaRemote.framework via dlopen (send commands work from signed apps,
// only queries are blocked).
// Safe as Sendable because all instance state is immutable after initialization
// (`handle` and `sendCommand` are `static let`).
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

  func isSystemAudioMuted() -> Bool? {
    guard let deviceID = Self.defaultOutputDeviceID() else { return nil }
    var address = Self.outputMuteAddress
    guard AudioObjectHasProperty(deviceID, &address) else { return nil }

    var muted: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
    guard status == noErr else { return nil }
    return muted != 0
  }

  func setSystemAudioMuted(_ muted: Bool) -> Bool {
    guard let deviceID = Self.defaultOutputDeviceID() else { return false }
    var address = Self.outputMuteAddress
    guard AudioObjectHasProperty(deviceID, &address) else { return false }

    var isSettable: DarwinBoolean = false
    let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
    guard settableStatus == noErr, isSettable.boolValue else { return false }

    var value: UInt32 = muted ? 1 : 0
    let status = AudioObjectSetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      UInt32(MemoryLayout<UInt32>.size),
      &value
    )
    return status == noErr
  }

  func isBluetoothInputDevice(_ deviceID: AudioDeviceID) -> Bool {
    guard deviceID != kAudioObjectUnknown else { return false }

    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var transportType: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      &transportType
    )
    guard status == noErr else { return false }
    return transportType == kAudioDeviceTransportTypeBluetooth
      || transportType == kAudioDeviceTransportTypeBluetoothLE
  }

  private static var outputMuteAddress: AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
  }

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
  private let timing: MediaPlaybackTiming
  private let sleep: @Sendable (Duration) async -> Void
  private var resumePending = false
  private var didMuteSystemAudio = false
  private var muteFallbackTask: Task<Void, Never>?
  private var restorationDelay: Duration = .zero
  private var recordingGeneration = 0

  init(
    client: MediaRemoteClient = MediaRemoteFramework(),
    timing: MediaPlaybackTiming = .live,
    sleep: @escaping @Sendable (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    }
  ) {
    self.client = client
    self.timing = timing
    self.sleep = sleep
  }

  func prepareForRecording(inputDeviceID: AudioDeviceID = kAudioObjectUnknown) {
    muteFallbackTask?.cancel()
    muteFallbackTask = nil
    recordingGeneration &+= 1
    let generation = recordingGeneration
    resumePending = false
    restorationDelay =
      client.isBluetoothInputDevice(inputDeviceID)
      ? timing.bluetoothRestorationDelay : .zero
    guard client.isSystemAudioActive() else {
      log.info("prepareForRecording: no system audio, skipping")
      return
    }

    if client.sendPause() {
      resumePending = true
      log.info("prepareForRecording: paused and armed resume")
    } else {
      log.info("prepareForRecording: pause command was not accepted")
    }

    scheduleMuteFallback(generation: generation)
  }

  func restoreAfterRecording() async {
    muteFallbackTask?.cancel()
    muteFallbackTask = nil

    let shouldResume = resumePending
    let shouldRestoreMute = didMuteSystemAudio
    let delay = restorationDelay
    let generation = recordingGeneration

    guard shouldResume || shouldRestoreMute else {
      restorationDelay = .zero
      log.info("restoreAfterRecording: no media restoration pending")
      return
    }

    if delay != .zero {
      log.info("restoreAfterRecording: waiting for Bluetooth output route to settle")
      await sleep(delay)
    }

    guard generation == recordingGeneration else {
      log.info("restoreAfterRecording: newer recording superseded pending restoration")
      return
    }

    defer {
      resumePending = false
      restorationDelay = .zero
    }

    restoreSystemAudioMuteIfOwned()

    guard shouldResume else {
      log.info("restoreAfterRecording: resumePending=false, skipping")
      return
    }

    guard client.sendPlay() else {
      log.info("restoreAfterRecording: play command was not accepted")
      return
    }

    log.info("restoreAfterRecording: resumed")
  }

  private func restoreSystemAudioMuteIfOwned() {
    guard didMuteSystemAudio else { return }
    defer { didMuteSystemAudio = false }

    guard client.isSystemAudioMuted() != false else {
      log.info("muteFallback: system audio was already unmuted")
      return
    }
    guard client.setSystemAudioMuted(false) else {
      log.error("muteFallback: failed to restore system audio")
      return
    }

    log.info("muteFallback: restored system audio")
  }

  private func scheduleMuteFallback(generation: Int) {
    let delay = timing.muteFallbackDelay
    let sleep = self.sleep
    muteFallbackTask = Task { @MainActor [weak self] in
      await sleep(delay)
      guard !Task.isCancelled, let self else { return }
      guard generation == self.recordingGeneration else { return }
      guard self.client.isSystemAudioActive() else {
        self.log.info("muteFallback: playback stopped, skipping system mute")
        return
      }
      guard self.client.isSystemAudioMuted() == false else {
        self.log.info("muteFallback: system audio was already muted")
        return
      }
      guard self.client.setSystemAudioMuted(true) else {
        self.log.info("muteFallback: output device could not be muted")
        return
      }

      self.didMuteSystemAudio = true
      self.log.info("muteFallback: muted active system audio")
    }
  }
}
