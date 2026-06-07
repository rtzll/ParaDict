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
    let (stream, continuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
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

actor ParakeetStreamingSession {
  private let chunkSource = StreamingChunkSource()
  private let agreementConfig = StreamingAgreementConfig()
  private let wordConverter = StreamingTokenWordConverter()
  private var agreementEngine: StreamingAgreementEngine

  private var manager: AsrManager?
  private var inputSampleRate: Double = 16_000
  private var chunkPumpTask: Task<Void, Never>?
  private var transcriptionLoopTask: Task<Void, Never>?
  private var audioBuffer = StreamingAudioBuffer()
  private var isTranscribing = false
  private var onPreviewUpdate: (@MainActor (StreamingPreviewUpdate) -> Void)?

  init() {
    agreementEngine = StreamingAgreementEngine(config: agreementConfig)
  }

  nonisolated func send(_ data: Data) {
    chunkSource.send(data)
  }

  func start(
    models: AsrModels,
    inputSampleRate: Double,
    onPreviewUpdate: @escaping @MainActor (StreamingPreviewUpdate) -> Void
  ) async throws {
    let manager = AsrManager(config: .default)
    try await manager.initialize(models: models)

    self.manager = manager
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
        try? await Task.sleep(for: .seconds(agreementConfig.transcribeIntervalSeconds))
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
    manager = nil
  }

  private func append(chunk: Data) {
    audioBuffer.append(chunk: chunk)
  }

  private func runTranscriptionPass() async {
    guard !isTranscribing else { return }
    guard let manager else { return }

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

    guard let buffer = Self.makePCMBuffer(from: window.samples, sampleRate: inputSampleRate) else {
      return
    }

    do {
      let result = try await manager.transcribe(buffer, source: .microphone)
      audioBuffer.markProcessed(upTo: absoluteSampleCount)

      guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          await onPreviewUpdate?(.partial(text))
        }
        return
      }

      let words = wordConverter.words(from: tokenTimings, timeOffset: window.timeOffset)
      guard !words.isEmpty else { return }

      let agreementResult = agreementEngine.process(words: words, confidence: result.confidence)
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
