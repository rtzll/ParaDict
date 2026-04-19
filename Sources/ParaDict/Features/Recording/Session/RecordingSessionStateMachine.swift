import Foundation

enum RecordingSessionState: Equatable, Sendable {
  case idle
  case starting
  case recording
  case processing
}

struct RecordingSessionStateMachine: Sendable {
  private(set) var state: RecordingSessionState

  init(state: RecordingSessionState = .idle) {
    self.state = state
  }

  @discardableResult
  mutating func beginStarting() -> Bool {
    transition(to: .starting, allowedFrom: [.idle])
  }

  @discardableResult
  mutating func markRecordingStarted() -> Bool {
    transition(to: .recording, allowedFrom: [.starting])
  }

  @discardableResult
  mutating func markStartFailed() -> Bool {
    transition(to: .idle, allowedFrom: [.starting])
  }

  @discardableResult
  mutating func beginProcessing() -> Bool {
    transition(to: .processing, allowedFrom: [.recording])
  }

  @discardableResult
  mutating func finishRecordingCancellation() -> Bool {
    transition(to: .idle, allowedFrom: [.recording])
  }

  @discardableResult
  mutating func finishProcessing() -> Bool {
    transition(to: .idle, allowedFrom: [.processing])
  }

  @discardableResult
  mutating func resetAfterInterruption() -> Bool {
    transition(to: .idle, allowedFrom: [.starting, .recording, .processing])
  }

  mutating func forceIdle() {
    state = .idle
  }

  private mutating func transition(
    to nextState: RecordingSessionState,
    allowedFrom allowedStates: Set<RecordingSessionState>
  ) -> Bool {
    guard allowedStates.contains(state) else { return false }
    state = nextState
    return true
  }
}
