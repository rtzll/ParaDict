import AVFoundation
@preconcurrency import FluidAudio
import Foundation

/// Wraps `AsyncStream.Continuation` so it can be stored in the actor and
/// yielded to from `nonisolated` callers. `Continuation` is internally
/// thread-safe by design.
private final class StreamingChunkSource: @unchecked Sendable {
  let stream: AsyncStream<Data>
  private let continuation: AsyncStream<Data>.Continuation

  init() {
    let (stream, continuation) = AsyncStream.makeStream(
      of: Data.self,
      bufferingPolicy: .bufferingNewest(32)
    )
    self.stream = stream
    self.continuation = continuation
  }

  func send(_ data: Data) {
    continuation.yield(data)
  }

  func finish() {
    continuation.finish()
  }
}

protocol LivePreviewClock: Sendable {
  func wait(for interval: TimeInterval) async throws
}

struct LivePreviewPassResult: Sendable {
  let text: String
  let words: [StreamingWord]
  let confidence: Float
}

typealias LivePreviewTranscriptionPass =
  @Sendable (
    _ samples: [Float],
    _ sampleRate: Double,
    _ timeOffset: TimeInterval
  ) async throws -> LivePreviewPassResult

private struct SystemLivePreviewClock: LivePreviewClock {
  func wait(for interval: TimeInterval) async throws {
    try await Task.sleep(for: .seconds(interval))
  }
}

actor LivePreviewSession {
  private let chunkSource = StreamingChunkSource()
  private let agreementConfig = StreamingAgreementConfig()
  private let wordConverter = StreamingTokenWordConverter()
  private let clock: LivePreviewClock
  private var agreementEngine: StreamingAgreementEngine

  private var transcriptionPass: LivePreviewTranscriptionPass?
  private var inputSampleRate: Double = 16_000
  private var chunkPumpTask: Task<Void, Never>?
  private var transcriptionLoopTask: Task<Void, Never>?
  private var audioBuffer = StreamingAudioBuffer()
  private var isTranscribing = false
  private var onPreviewUpdate: (@MainActor (StreamingPreviewUpdate) -> Void)?

  init(
    clock: LivePreviewClock = SystemLivePreviewClock(),
    transcriptionPass: LivePreviewTranscriptionPass? = nil
  ) {
    self.clock = clock
    self.transcriptionPass = transcriptionPass
    agreementEngine = StreamingAgreementEngine(config: agreementConfig)
  }

  nonisolated func send(_ data: Data) {
    chunkSource.send(data)
  }

  func accept(_ data: Data) {
    append(chunk: data)
  }

  func start(
    models: AsrModels,
    inputSampleRate: Double,
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) async throws {
    let manager = AsrManager(config: .default)
    try await manager.initialize(models: models)

    let wordConverter = self.wordConverter
    transcriptionPass = { samples, sampleRate, timeOffset in
      guard let buffer = Self.makePCMBuffer(from: samples, sampleRate: sampleRate) else {
        return LivePreviewPassResult(text: "", words: [], confidence: 0)
      }
      let result = try await manager.transcribe(buffer, source: .microphone)
      let words = wordConverter.words(from: result.tokenTimings ?? [], timeOffset: timeOffset)
      return LivePreviewPassResult(
        text: result.text,
        words: words,
        confidence: result.confidence
      )
    }
    begin(inputSampleRate: inputSampleRate, onPreviewUpdate: onPreviewUpdate)
  }

  func startPrepared(
    inputSampleRate: Double,
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) {
    precondition(transcriptionPass != nil, "A prepared transcription pass is required")
    begin(inputSampleRate: inputSampleRate, onPreviewUpdate: onPreviewUpdate)
  }

  private func begin(
    inputSampleRate: Double,
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) {
    self.inputSampleRate = inputSampleRate
    self.onPreviewUpdate = onPreviewUpdate
    self.audioBuffer.reset()
    self.isTranscribing = false
    agreementEngine.reset()

    chunkPumpTask = Task { [chunkSource] in
      for await chunk in chunkSource.stream {
        self.append(chunk: chunk)
      }
    }

    transcriptionLoopTask = Task {
      while !Task.isCancelled {
        do {
          try await clock.wait(for: agreementConfig.transcribeIntervalSeconds)
        } catch {
          return
        }
        await self.runTranscriptionPass()
      }
    }
  }

  func cancel() async {
    chunkSource.finish()
    chunkPumpTask?.cancel()
    transcriptionLoopTask?.cancel()
    chunkPumpTask = nil
    transcriptionLoopTask = nil
    audioBuffer.reset()
    isTranscribing = false
    onPreviewUpdate = nil
    agreementEngine.reset()
    transcriptionPass = nil
  }

  private func append(chunk: Data) {
    audioBuffer.append(chunk: chunk)
  }

  private func runTranscriptionPass() async {
    guard !isTranscribing else { return }
    guard let transcriptionPass else { return }

    let absoluteSampleCount = audioBuffer.absoluteSampleCount
    guard
      audioBuffer.hasEnoughAudioToProcess(inputSampleRate: inputSampleRate, minNewAudioSeconds: 0.5)
    else { return }

    isTranscribing = true
    defer { isTranscribing = false }

    let seekTime =
      agreementEngine.hypothesisStartTime > 0
      ? agreementEngine.hypothesisStartTime : agreementEngine.confirmedEndTime
    guard
      let window = audioBuffer.transcriptionWindow(
        startingAt: seekTime,
        inputSampleRate: inputSampleRate,
        trailingSilenceSeconds: agreementConfig.trailingSilenceSeconds
      )
    else {
      return
    }

    do {
      let result = try await transcriptionPass(
        window.samples,
        inputSampleRate,
        window.timeOffset
      )
      audioBuffer.markProcessed(upTo: absoluteSampleCount)

      guard !result.words.isEmpty else {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          await onPreviewUpdate?(.partial(text))
        }
        return
      }

      let agreementResult = agreementEngine.process(
        words: result.words,
        confidence: result.confidence
      )
      if !agreementResult.newlyConfirmedText.isEmpty {
        await onPreviewUpdate?(.committed(agreementResult.newlyConfirmedText))
      }
      if !agreementResult.fullText.isEmpty {
        await onPreviewUpdate?(.partial(agreementResult.fullText))
      }

      let trimSample = max(0, Int(agreementEngine.hypothesisStartTime * inputSampleRate))
      audioBuffer.trim(beforeAbsoluteSample: trimSample)
    } catch {
      // Keep recording alive; preview can recover on the next pass.
    }
  }

  private static func makePCMBuffer(from samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer?
  {
    guard !samples.isEmpty else { return nil }
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      )
    else {
      return nil
    }

    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
      )
    else {
      return nil
    }

    buffer.frameLength = AVAudioFrameCount(samples.count)
    guard let destination = buffer.floatChannelData?[0] else { return nil }
    samples.withUnsafeBufferPointer { source in
      destination.update(from: source.baseAddress!, count: samples.count)
    }
    return buffer
  }
}
