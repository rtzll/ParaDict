import Foundation

/// Converts successive microphone chunks onto one absolute output timeline.
/// Computing each output position from its absolute index prevents chunk
/// boundaries from resetting the fractional sample-rate conversion phase.
private struct ContinuousAudioResampler: Sendable {
  private var inputSampleRate = 16_000.0
  private var outputSampleRate = 16_000.0
  private var bufferedSamples: [Float] = []
  private var bufferStartIndex: Int64 = 0
  private var totalInputSampleCount: Int64 = 0
  private var outputSampleCount: Int64 = 0

  mutating func reset(inputSampleRate: Double, outputSampleRate: Double) {
    precondition(inputSampleRate > 0)
    precondition(outputSampleRate > 0)
    self.inputSampleRate = inputSampleRate
    self.outputSampleRate = outputSampleRate
    bufferedSamples = []
    bufferStartIndex = 0
    totalInputSampleCount = 0
    outputSampleCount = 0
  }

  mutating func process(_ input: [Float]) -> [Float] {
    guard !input.isEmpty else { return [] }
    guard inputSampleRate != outputSampleRate else {
      totalInputSampleCount += Int64(input.count)
      outputSampleCount += Int64(input.count)
      return input
    }

    bufferedSamples.append(contentsOf: input)
    totalInputSampleCount += Int64(input.count)

    let estimatedOutputCount = Int(
      ceil(Double(input.count) * outputSampleRate / inputSampleRate)
    )
    var output: [Float] = []
    output.reserveCapacity(estimatedOutputCount)

    while true {
      let sourcePosition =
        Double(outputSampleCount) * inputSampleRate / outputSampleRate
      let lowerIndex = Int64(sourcePosition.rounded(.down))
      let upperIndex = lowerIndex + 1
      guard upperIndex < totalInputSampleCount else { break }

      let lowerBufferIndex = Int(lowerIndex - bufferStartIndex)
      let upperBufferIndex = Int(upperIndex - bufferStartIndex)
      let fraction = Float(sourcePosition - Double(lowerIndex))
      let lowerSample = bufferedSamples[lowerBufferIndex]
      let upperSample = bufferedSamples[upperBufferIndex]
      output.append(lowerSample + fraction * (upperSample - lowerSample))
      outputSampleCount += 1
    }

    discardConsumedInput()
    return output
  }

  private mutating func discardConsumedInput() {
    let nextSourcePosition =
      Double(outputSampleCount) * inputSampleRate / outputSampleRate
    let nextLowerIndex = Int64(nextSourcePosition.rounded(.down))
    let discardCount = min(
      max(0, Int(nextLowerIndex - bufferStartIndex)),
      bufferedSamples.count
    )
    guard discardCount > 0 else { return }

    bufferedSamples.removeFirst(discardCount)
    bufferStartIndex += Int64(discardCount)
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

struct StreamingAudioBuffer: Sendable {
  private var samples: [Float] = []
  private var resampler = ContinuousAudioResampler()
  private(set) var trimmedSampleCount = 0
  private(set) var lastProcessedSampleCount = 0

  var absoluteSampleCount: Int { trimmedSampleCount + samples.count }

  mutating func reset() {
    samples = []
    trimmedSampleCount = 0
    lastProcessedSampleCount = 0
    resampler.reset(inputSampleRate: 16_000, outputSampleRate: 16_000)
  }

  mutating func reset(inputSampleRate: Double, outputSampleRate: Double) {
    samples = []
    trimmedSampleCount = 0
    lastProcessedSampleCount = 0
    resampler.reset(
      inputSampleRate: inputSampleRate,
      outputSampleRate: outputSampleRate
    )
  }

  mutating func append(chunk: Data) {
    let sampleCount = chunk.count / MemoryLayout<Float>.size
    guard sampleCount > 0 else { return }

    chunk.withUnsafeBytes { rawBuffer in
      let floats = rawBuffer.bindMemory(to: Float.self)
      let resampled = resampler.process(Array(floats))
      samples.append(contentsOf: resampled)
    }
  }

  func hasEnoughAudioToProcess(inputSampleRate: Double, minNewAudioSeconds: Double) -> Bool {
    let minNewSamples = Int(inputSampleRate * minNewAudioSeconds)
    guard absoluteSampleCount - lastProcessedSampleCount >= minNewSamples else { return false }
    return absoluteSampleCount >= Int(inputSampleRate)
  }

  func transcriptionWindow(
    startingAt seekTime: Double,
    inputSampleRate: Double,
    trailingSilenceSeconds: Double
  ) -> StreamingTranscriptionWindow? {
    let seekSample = max(0, Int(seekTime * inputSampleRate))
    let bufferRelativeSeek = max(0, seekSample - trimmedSampleCount)
    return StreamingTranscriptionWindow.make(
      audioBuffer: samples,
      trimmedSampleCount: trimmedSampleCount,
      bufferRelativeSeek: bufferRelativeSeek,
      inputSampleRate: inputSampleRate,
      trailingSilenceSeconds: trailingSilenceSeconds
    )
  }

  mutating func markProcessed(upTo absoluteSampleCount: Int) {
    lastProcessedSampleCount = absoluteSampleCount
  }

  mutating func trim(beforeAbsoluteSample trimSample: Int) {
    let samplesToTrim = trimSample - trimmedSampleCount
    guard samplesToTrim > 0 else { return }

    let actualTrim = min(samplesToTrim, samples.count)
    samples.removeFirst(actualTrim)
    trimmedSampleCount += actualTrim
  }
}
