import Testing

@testable import ParaDict

struct RecordingSessionStateMachineTests {
  @Test func happyPathTransitionsFromIdleToProcessingAndBack() {
    var stateMachine = RecordingSessionStateMachine()

    #expect(stateMachine.state == .idle)
    let started = stateMachine.beginStarting()
    #expect(started)
    #expect(stateMachine.state == .starting)
    let markedRecording = stateMachine.markRecordingStarted()
    #expect(markedRecording)
    #expect(stateMachine.state == .recording)
    let beganProcessing = stateMachine.beginProcessing()
    #expect(beganProcessing)
    #expect(stateMachine.state == .processing)
    let finishedProcessing = stateMachine.finishProcessing()
    #expect(finishedProcessing)
    #expect(stateMachine.state == .idle)
  }

  @Test func rejectsStaleOrOutOfOrderTransitions() {
    var stateMachine = RecordingSessionStateMachine()

    let beginProcessingFromIdle = stateMachine.beginProcessing()
    let finishProcessingFromIdle = stateMachine.finishProcessing()
    let cancelFromIdle = stateMachine.finishRecordingCancellation()
    #expect(!beginProcessingFromIdle)
    #expect(!finishProcessingFromIdle)
    #expect(!cancelFromIdle)
    #expect(stateMachine.state == .idle)

    let beginStarting = stateMachine.beginStarting()
    let finishProcessingFromStarting = stateMachine.finishProcessing()
    let cancelFromStarting = stateMachine.finishRecordingCancellation()
    #expect(beginStarting)
    #expect(!finishProcessingFromStarting)
    #expect(!cancelFromStarting)
    #expect(stateMachine.state == .starting)

    let markRecordingStarted = stateMachine.markRecordingStarted()
    let markRecordingStartedAgain = stateMachine.markRecordingStarted()
    let markStartFailedFromRecording = stateMachine.markStartFailed()
    #expect(markRecordingStarted)
    #expect(!markRecordingStartedAgain)
    #expect(!markStartFailedFromRecording)
    #expect(stateMachine.state == .recording)
  }

  @Test func resetsToIdleFromAnyActivePhase() {
    var stateMachine = RecordingSessionStateMachine(state: .starting)
    let resetFromStarting = stateMachine.resetAfterInterruption()
    #expect(resetFromStarting)
    #expect(stateMachine.state == .idle)

    stateMachine = RecordingSessionStateMachine(state: .recording)
    let resetFromRecording = stateMachine.resetAfterInterruption()
    #expect(resetFromRecording)
    #expect(stateMachine.state == .idle)

    stateMachine = RecordingSessionStateMachine(state: .processing)
    let resetFromProcessing = stateMachine.resetAfterInterruption()
    #expect(resetFromProcessing)
    #expect(stateMachine.state == .idle)
  }
}
