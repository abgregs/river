import Testing
@testable import River

@Suite("TapStateMachine")
struct TapStateMachineTests {
    // The double-tap window is timing-sensitive, so the machine takes an injected
    // clock; tests advance a captured `TimeInterval` rather than sleep. Window is
    // 400 ms throughout. `isRecording` stands in for the session's state.

    @MainActor
    @Test("single tap: a tap starts when idle and stops while recording")
    func singleTapStartsAndStops() {
        let machine = TapStateMachine(mode: .singleTap, windowMs: 400, now: { 0 })
        #expect(machine.handleTap(isRecording: false) == .start)
        #expect(machine.handleTap(isRecording: true) == .stop)
    }

    @MainActor
    @Test("single tap: after a refused start the next tap starts again")
    func singleTapAfterRefusedStart() {
        // The session can refuse a start (model not ready, permission denied, still
        // transcribing). It stays idle, so the next tap must be another start, not a
        // stop for a recording that never began.
        let machine = TapStateMachine(mode: .singleTap, windowMs: 400, now: { 0 })
        #expect(machine.handleTap(isRecording: false) == .start)   // refused
        #expect(machine.handleTap(isRecording: false) == .start)
    }

    @MainActor
    @Test("double tap within the window starts")
    func doubleTapWithinWindowStarts() {
        var clock: Double = 0
        let machine = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        #expect(machine.handleTap(isRecording: false) == .none)   // first tap → awaiting
        clock = 0.300                                              // 300 ms later
        #expect(machine.handleTap(isRecording: false) == .start)  // within 400 ms
    }

    @MainActor
    @Test("double tap outside the window does not start; it restarts detection")
    func doubleTapOutsideWindowRestarts() {
        var clock: Double = 0
        let machine = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        #expect(machine.handleTap(isRecording: false) == .none)   // first tap @ 0
        clock = 1.0                                                // 1000 ms later — too slow
        #expect(machine.handleTap(isRecording: false) == .none)   // becomes the new first tap
        clock = 1.2                                                // 200 ms after the new first tap
        #expect(machine.handleTap(isRecording: false) == .start)  // now within the window
    }

    @MainActor
    @Test("double tap exactly at the window boundary starts")
    func doubleTapBoundaryStarts() {
        var clock: Double = 0
        let machine = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        #expect(machine.handleTap(isRecording: false) == .none)
        clock = 0.400                                              // exactly 400 ms — inclusive
        #expect(machine.handleTap(isRecording: false) == .start)
    }

    @MainActor
    @Test("double tap stops on a single tap")
    func doubleTapStopsOnSingleTap() {
        var clock: Double = 0
        let machine = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        _ = machine.handleTap(isRecording: false)                  // first tap
        clock = 0.100
        #expect(machine.handleTap(isRecording: false) == .start)  // the session starts recording
        clock = 5.0                                                // much later — a lone tap
        #expect(machine.handleTap(isRecording: true) == .stop)    // a single tap stops
    }

    @MainActor
    @Test("double tap: after a refused start the next pair starts again")
    func doubleTapAfterRefusedStart() {
        var clock: Double = 0
        let machine = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        _ = machine.handleTap(isRecording: false)
        clock = 0.100
        #expect(machine.handleTap(isRecording: false) == .start)  // refused
        clock = 2.0
        #expect(machine.handleTap(isRecording: false) == .none)   // a fresh first tap, not a stop
        clock = 2.1
        #expect(machine.handleTap(isRecording: false) == .start)
    }

    @MainActor
    @Test("setMode clears a pending double tap and still stops a live recording")
    func setModeClearsPendingTap() {
        var clock: Double = 0
        let awaiting = TapStateMachine(mode: .doubleTap, windowMs: 400, now: { clock })
        #expect(awaiting.handleTap(isRecording: false) == .none)   // pending second tap
        awaiting.setMode(.singleTap)                                // clears the half-done detection
        #expect(awaiting.handleTap(isRecording: false) == .start)  // a fresh single-tap start

        let recording = TapStateMachine(mode: .singleTap, windowMs: 400, now: { 0 })
        recording.setMode(.doubleTap)                               // live mode change mid-recording
        #expect(recording.handleTap(isRecording: true) == .stop)   // the recording is still stoppable
    }

    @MainActor
    @Test("hold mode is never interpreted here")
    func holdReturnsNone() {
        let machine = TapStateMachine(mode: .hold, windowMs: 400, now: { 0 })
        #expect(machine.handleTap(isRecording: false) == .none)
        #expect(machine.handleTap(isRecording: true) == .none)
    }
}
