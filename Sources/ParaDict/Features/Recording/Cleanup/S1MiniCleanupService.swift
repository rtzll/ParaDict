import Foundation
import MLXLLM
import MLXLMCommon
import NaturalLanguage
import Observation
import os.log

struct S1MiniPrompt {
  struct AdditionalContext: Equatable, Sendable {
    let enableThinking: Bool
  }

  static let systemMessage =
    "You are a text normalizer for speech-to-text transcripts. The input begins "
    + "with a control line specifying the styling, structure, and context settings; "
    + "clean the transcript to match those settings and output only the cleaned text."

  static let controlLine =
    "[Styling: semi-formal] [Structure: prose] [Context: general]"

  static let additionalContext = AdditionalContext(enableThinking: false)

  static func userMessage(for transcript: String) -> String {
    "\(controlLine)\n\(transcript)"
  }
}

@MainActor
struct TranscriptChunker {
  let maximumTokens: Int

  func chunks(
    for text: String,
    tokenCount: (String) async -> Int
  ) async -> [String] {
    let sentences = sentences(in: text)
    guard !sentences.isEmpty else { return [] }

    var result: [String] = []
    var current = ""

    for sentence in sentences {
      if await tokenCount(sentence) > maximumTokens {
        if !current.isEmpty {
          result.append(current)
          current = ""
        }
        result.append(contentsOf: await wordChunks(for: sentence, tokenCount: tokenCount))
        continue
      }

      let candidate = current.isEmpty ? sentence : "\(current) \(sentence)"
      if await tokenCount(candidate) <= maximumTokens {
        current = candidate
      } else {
        result.append(current)
        current = sentence
      }
    }

    if !current.isEmpty {
      result.append(current)
    }
    return result
  }

  private func sentences(in text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    var result: [String] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
      if !sentence.isEmpty {
        result.append(sentence)
      }
      return true
    }
    return result
  }

  private func wordChunks(
    for text: String,
    tokenCount: (String) async -> Int
  ) async -> [String] {
    let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    var result: [String] = []
    var current = ""

    for word in words {
      let candidate = current.isEmpty ? word : "\(current) \(word)"
      let candidateFits: Bool
      if current.isEmpty {
        candidateFits = true
      } else {
        candidateFits = await tokenCount(candidate) <= maximumTokens
      }
      if candidateFits {
        current = candidate
      } else {
        result.append(current)
        current = word
      }
    }

    if !current.isEmpty {
      result.append(current)
    }
    return result
  }
}

private let cleanupLog = Logger(subsystem: Logger.subsystem, category: "S1MiniCleanup")

/// Cleans up raw Parakeet transcripts locally with Superwhisper's open-weights
/// S1-mini model (Qwen3-0.6B fine-tune, MLX 4-bit).
///
/// The model is downloaded and loaded lazily when cleanup is enabled and the
/// result is used only when the model is ready; any failure falls back to the
/// raw transcript.
@MainActor
@Observable
final class S1MiniCleanupService: TranscriptCleanupProviding, Sendable {
  typealias ModelLoader = @MainActor @Sendable () async throws -> ModelContainer

  enum ModelState: Equatable {
    case idle
    case preparing
    case ready
    case failed(String)
  }

  private static let modelID = "mlx-community/S1-mini-MLX-4bit"
  private static let modelRevision = "5cbd7aec3401144f88a331d385c40b65fd2548eb"
  private static let enabledKey = "TranscriptCleanupEnabled"
  private static let maximumInputTokens = 900
  private(set) var isEnabled: Bool
  private(set) var state: ModelState = .idle

  @ObservationIgnored private var container: ModelContainer?
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  @ObservationIgnored private var loadGeneration: UUID?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let modelLoader: ModelLoader

  init(
    enabled: Bool? = nil,
    defaults: UserDefaults = .standard,
    modelLoader: @escaping ModelLoader = {
      try await loadModelContainer(
        configuration: ModelConfiguration(
          id: S1MiniCleanupService.modelID,
          revision: S1MiniCleanupService.modelRevision
        ))
    }
  ) {
    self.defaults = defaults
    self.modelLoader = modelLoader
    isEnabled = enabled ?? defaults.bool(forKey: Self.enabledKey)
    if isEnabled {
      prepare()
    }
  }

  var menuPresentation: CleanupMenuPresentation {
    CleanupMenuPresentation(
      isEnabled: isEnabled,
      status: CleanupStatusPresentation(state: state)
    )
  }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    defaults.set(enabled, forKey: Self.enabledKey)

    if enabled {
      prepare()
    } else {
      loadGeneration = nil
      loadTask?.cancel()
      loadTask = nil
      container = nil
      state = .idle
    }
  }

  /// Loads the model in the background so the first dictation doesn't pay
  /// the download and load cost.
  func prepare() {
    guard isEnabled else { return }
    if case .ready = state { return }
    if loadTask != nil { return }

    let generation = UUID()
    loadGeneration = generation
    state = .preparing
    loadTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.loadGeneration == generation {
          self.loadTask = nil
        }
      }

      do {
        let container = try await self.modelLoader()
        guard
          !Task.isCancelled,
          self.loadGeneration == generation,
          self.isEnabled
        else { return }
        self.container = container
        self.state = .ready
      } catch {
        guard
          !Task.isCancelled,
          self.loadGeneration == generation,
          self.isEnabled
        else { return }
        cleanupLog.error("Failed to load S1-mini by Superwhisper: \(error.localizedDescription)")
        self.state = .failed(error.localizedDescription)
      }
    }
  }

  func cleanup(_ text: String) async -> TranscriptCleanupResult {
    guard isEnabled, case .ready = state, let container else { return .unavailable }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .cleaned("")
    }

    let chunker = TranscriptChunker(maximumTokens: Self.maximumInputTokens)
    let chunks = await chunker.chunks(for: text) { chunk in
      await container.encode(chunk).count
    }
    guard !chunks.isEmpty else { return .cleaned("") }

    var cleanedChunks: [String] = []
    for chunk in chunks {
      guard isEnabled else { return .unavailable }
      switch await respond(chunk, container: container) {
      case .cleaned(let cleaned):
        if !cleaned.isEmpty {
          cleanedChunks.append(cleaned)
        }
      case .unavailable:
        return .unavailable
      }
    }
    guard isEnabled else { return .unavailable }
    return .cleaned(cleanedChunks.joined(separator: " "))
  }

  static func outputTokenBudget(forInputTokens inputTokens: Int) -> Int {
    max(64, Int(ceil(Double(inputTokens) * 1.3)) + 32)
  }

  private func respond(
    _ text: String,
    container: ModelContainer
  ) async -> TranscriptCleanupResult {
    let inputTokens = await container.encode(text).count
    let outputTokens = Self.outputTokenBudget(forInputTokens: inputTokens)
    let session = ChatSession(
      container,
      instructions: S1MiniPrompt.systemMessage,
      generateParameters: GenerateParameters(maxTokens: outputTokens, temperature: 0),
      additionalContext: [
        "enable_thinking": S1MiniPrompt.additionalContext.enableThinking
      ]
    )

    do {
      let cleaned = try await session.respond(to: S1MiniPrompt.userMessage(for: text))
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
      return .cleaned(cleaned)
    } catch {
      cleanupLog.error("S1-mini cleanup failed: \(error.localizedDescription)")
      return .unavailable
    }
  }
}

struct CleanupMenuPresentation: Equatable, Sendable {
  let isEnabled: Bool
  let status: CleanupStatusPresentation
}

struct CleanupStatusPresentation: Equatable, Sendable {
  enum Status: Equatable, Sendable {
    case off
    case preparing
    case ready
    case failed
  }

  let status: Status
  let failureMessage: String?

  init(state: S1MiniCleanupService.ModelState) {
    switch state {
    case .idle:
      status = .off
      failureMessage = nil
    case .preparing:
      status = .preparing
      failureMessage = nil
    case .ready:
      status = .ready
      failureMessage = nil
    case .failed(let message):
      status = .failed
      failureMessage = message
    }
  }

  var description: String {
    switch status {
    case .off: return "Off"
    case .preparing: return "Downloading model…"
    case .ready: return "S1-mini by Superwhisper ready"
    case .failed: return "Failed to load"
    }
  }
}
