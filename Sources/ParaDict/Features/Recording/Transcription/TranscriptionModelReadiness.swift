import Foundation
import Observation

struct ModelReadinessFailure: Equatable, Sendable {
  let title: String
  let message: String

  init(title: String, message: String) {
    self.title = title
    self.message = message
  }

  init(error: Error) {
    self.init(
      title: "Model Load Failed",
      message: error.localizedDescription
    )
  }
}

struct ModelReadinessMenuPresentation: Equatable, Sendable {
  enum Tone: Sendable {
    case ready
    case pending
    case failed
  }

  let title: String
  let systemImage: String
  let tone: Tone
  let showsProgress: Bool
  let retryTitle: String?
}

@MainActor
protocol RecordingModelReadinessChecking: AnyObject {
  var isReadyForRecording: Bool { get }
  var menuPresentation: ModelReadinessMenuPresentation { get }
  func preload()
  func retry()
  func recordingStartFailure() -> ModelReadinessFailure?
}

@MainActor
protocol TranscriptionModelLoadingResetting: AnyObject {
  func resetModelLoading()
}

@Observable
@MainActor
final class TranscriptionModelReadiness: Sendable, RecordingModelReadinessChecking {
  enum State: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded
    case failed(ModelReadinessFailure)
  }

  private let provider: TranscriptionProviding
  private(set) var state: State
  @ObservationIgnored
  private var loadTask: Task<Void, Never>?
  @ObservationIgnored
  private var loadGeneration = 0

  init(provider: TranscriptionProviding) {
    self.provider = provider
    self.state = provider.isInitialized ? .loaded : .notLoaded
  }

  deinit {
    loadTask?.cancel()
  }

  var isReadyForRecording: Bool {
    if case .loaded = state { return true }
    return false
  }

  var menuPresentation: ModelReadinessMenuPresentation {
    switch state {
    case .notLoaded:
      ModelReadinessMenuPresentation(
        title: "Model Not Ready",
        systemImage: "waveform.badge.exclamationmark",
        tone: .pending,
        showsProgress: false,
        retryTitle: "Load"
      )
    case .loading:
      ModelReadinessMenuPresentation(
        title: "Loading Parakeet...",
        systemImage: "waveform.badge.ellipsis",
        tone: .pending,
        showsProgress: true,
        retryTitle: nil
      )
    case .loaded:
      ModelReadinessMenuPresentation(
        title: "Ready",
        systemImage: "waveform",
        tone: .ready,
        showsProgress: false,
        retryTitle: nil
      )
    case .failed:
      ModelReadinessMenuPresentation(
        title: "Model Load Failed",
        systemImage: "exclamationmark.triangle.fill",
        tone: .failed,
        showsProgress: false,
        retryTitle: "Retry"
      )
    }
  }

  func preload() {
    startLoading(resetExistingLoad: false)
  }

  func retry() {
    startLoading(resetExistingLoad: true)
  }

  func recordingStartFailure() -> ModelReadinessFailure? {
    switch state {
    case .loaded:
      return nil
    case .loading:
      return ModelReadinessFailure(
        title: "Model Loading",
        message: "Please wait for Parakeet to finish loading."
      )
    case .failed(let failure):
      return ModelReadinessFailure(
        title: failure.title,
        message: "\(failure.message) Try Retry from the menu bar."
      )
    case .notLoaded:
      preload()
      return ModelReadinessFailure(
        title: "Model Not Ready",
        message: "Parakeet is still preparing. Please try again in a moment."
      )
    }
  }

  private func startLoading(resetExistingLoad: Bool) {
    if case .loaded = state, !resetExistingLoad { return }
    if case .loading = state, !resetExistingLoad { return }

    loadGeneration += 1
    let generation = loadGeneration
    loadTask?.cancel()

    if resetExistingLoad, let resettableProvider = provider as? TranscriptionModelLoadingResetting {
      resettableProvider.resetModelLoading()
    }

    state = .loading
    loadTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await self.provider.initialize()
        guard self.loadGeneration == generation, !Task.isCancelled else { return }
        self.state = .loaded
        self.loadTask = nil
      } catch {
        guard self.loadGeneration == generation, !Task.isCancelled else { return }
        self.state = .failed(ModelReadinessFailure(error: error))
        self.loadTask = nil
      }
    }
  }
}

extension ParakeetProvider: TranscriptionModelLoadingResetting {
  func resetModelLoading() {
    unload()
  }
}
