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

struct StreamingTranscriptionWindow: Equatable, Sendable {
  let samples: [Float]
  let timeOffset: Double

  static func make(
    audioBuffer: [Float],
    trimmedSampleCount: Int,
    bufferRelativeSeek: Int,
    inputSampleRate: Double,
    trailingSilenceSeconds: Double,
    maxSinglePassSeconds: Double = 15.0
  ) -> StreamingTranscriptionWindow? {
    guard bufferRelativeSeek < audioBuffer.count else { return nil }

    var samples = Array(audioBuffer[bufferRelativeSeek...])
    guard samples.count >= Int(inputSampleRate) else { return nil }

    let maxSinglePassSamples = Int(inputSampleRate * maxSinglePassSeconds)
    let trailingSilenceSamples = Int(inputSampleRate * trailingSilenceSeconds)
    if trailingSilenceSamples > 0, samples.count + trailingSilenceSamples <= maxSinglePassSamples {
      samples += [Float](repeating: 0, count: trailingSilenceSamples)
    }

    return StreamingTranscriptionWindow(
      samples: samples,
      timeOffset: Double(trimmedSampleCount + bufferRelativeSeek) / inputSampleRate
    )
  }
}

actor ParakeetStreamingSession {
  private let chunkSource = StreamingChunkSource()
  private let agreementConfig = StreamingAgreementConfig()
  private var agreementEngine: StreamingAgreementEngine

  private var manager: AsrManager?
  private var inputSampleRate: Double = 16_000
  private var chunkPumpTask: Task<Void, Never>?
  private var transcriptionLoopTask: Task<Void, Never>?
  private var audioBuffer: [Float] = []
  private var trimmedSampleCount = 0
  private var lastProcessedSampleCount = 0
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
    self.audioBuffer = []
    self.trimmedSampleCount = 0
    self.lastProcessedSampleCount = 0
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
    audioBuffer = []
    trimmedSampleCount = 0
    lastProcessedSampleCount = 0
    isTranscribing = false
    onPreviewUpdate = nil
    agreementEngine.reset()
    manager = nil
  }

  private func append(chunk: Data) {
    let sampleCount = chunk.count / MemoryLayout<Float>.size
    guard sampleCount > 0 else { return }

    chunk.withUnsafeBytes { rawBuffer in
      let floats = rawBuffer.bindMemory(to: Float.self)
      audioBuffer.append(contentsOf: floats)
    }
  }

  private func runTranscriptionPass() async {
    guard !isTranscribing else { return }
    guard let manager else { return }

    let absoluteSampleCount = trimmedSampleCount + audioBuffer.count
    let minNewSamples = Int(inputSampleRate * 0.5)
    guard absoluteSampleCount - lastProcessedSampleCount >= minNewSamples else { return }
    guard absoluteSampleCount >= Int(inputSampleRate) else { return }

    isTranscribing = true
    defer { isTranscribing = false }

    let seekTime =
      agreementEngine.hypothesisStartTime > 0
      ? agreementEngine.hypothesisStartTime : agreementEngine.confirmedEndTime
    let seekSample = max(0, Int(seekTime * inputSampleRate))
    let bufferRelativeSeek = max(0, seekSample - trimmedSampleCount)
    guard bufferRelativeSeek < audioBuffer.count else { return }

    guard
      let window = StreamingTranscriptionWindow.make(
        audioBuffer: audioBuffer,
        trimmedSampleCount: trimmedSampleCount,
        bufferRelativeSeek: bufferRelativeSeek,
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
      lastProcessedSampleCount = absoluteSampleCount

      guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty else {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
          await onPreviewUpdate?(.partial(text))
        }
        return
      }

      let words = Self.mergeTokensToWords(tokenTimings, timeOffset: window.timeOffset)
      guard !words.isEmpty else { return }

      let agreementResult = agreementEngine.process(words: words, confidence: result.confidence)
      if !agreementResult.newlyConfirmedText.isEmpty {
        await onPreviewUpdate?(.committed(agreementResult.newlyConfirmedText))
      }
      if !agreementResult.fullText.isEmpty {
        await onPreviewUpdate?(.partial(agreementResult.fullText))
      }

      let trimSample = max(0, Int(agreementEngine.hypothesisStartTime * inputSampleRate))
      let samplesToTrim = trimSample - trimmedSampleCount
      if samplesToTrim > 0 {
        let actualTrim = min(samplesToTrim, audioBuffer.count)
        audioBuffer.removeFirst(actualTrim)
        trimmedSampleCount += actualTrim
      }
    } catch {
      // Keep recording alive; preview can recover on the next pass.
    }
  }

  private static func mergeTokensToWords(_ timings: [TokenTiming], timeOffset: Double)
    -> [StreamingWord]
  {
    guard !timings.isEmpty else { return [] }

    var words: [StreamingWord] = []
    var currentText = ""
    var startTime = 0.0
    var endTime = 0.0
    var confidences: [Float] = []

    for timing in timings {
      let token = timing.token
      let startsWord = token.hasPrefix("▁") || token.hasPrefix(" ")

      if startsWord {
        if !currentText.isEmpty {
          let confidence =
            confidences.isEmpty ? 1.0 : confidences.reduce(0, +) / Float(confidences.count)
          words.append(
            StreamingWord(
              text: currentText,
              startTime: startTime + timeOffset,
              endTime: endTime + timeOffset,
              confidence: confidence
            )
          )
        }

        currentText = token.trimmingCharacters(in: .whitespaces).replacingOccurrences(
          of: "▁", with: "")
        startTime = timing.startTime
        endTime = timing.endTime
        confidences = [timing.confidence]
      } else {
        if currentText.isEmpty {
          startTime = timing.startTime
        }
        currentText += token
        endTime = timing.endTime
        confidences.append(timing.confidence)
      }
    }

    if !currentText.isEmpty {
      let confidence =
        confidences.isEmpty ? 1.0 : confidences.reduce(0, +) / Float(confidences.count)
      words.append(
        StreamingWord(
          text: currentText,
          startTime: startTime + timeOffset,
          endTime: endTime + timeOffset,
          confidence: confidence
        )
      )
    }

    return words
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
