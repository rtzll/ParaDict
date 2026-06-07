import Foundation

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
  private(set) var trimmedSampleCount = 0
  private(set) var lastProcessedSampleCount = 0

  var absoluteSampleCount: Int { trimmedSampleCount + samples.count }

  mutating func reset() {
    samples = []
    trimmedSampleCount = 0
    lastProcessedSampleCount = 0
  }

  mutating func append(chunk: Data) {
    let sampleCount = chunk.count / MemoryLayout<Float>.size
    guard sampleCount > 0 else { return }

    chunk.withUnsafeBytes { rawBuffer in
      let floats = rawBuffer.bindMemory(to: Float.self)
      samples.append(contentsOf: floats)
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
