import Testing
@testable import River

@Suite("Turn")
struct TurnTests {
    @MainActor
    @Test("callers waiting for the turn take it in the order they asked", .timeLimit(.minutes(1)))
    func waitersKeepTheirOrder() async {
        // Paste last pressed twice must type in the order pressed, and decodes must reach the
        // engine in the order asked (planning 0039).
        let turn = Turn()
        var order: [Int] = []
        await turn.take()
        let callers = (1...3).map { index in
            Task { @MainActor in
                await turn.take()
                order.append(index)
                turn.pass()
            }
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(order.isEmpty)
        turn.pass()
        for caller in callers { await caller.value }
        #expect(order == [1, 2, 3])
    }

    @MainActor
    @Test("a turn passed with no one waiting is free for the next caller at once", .timeLimit(.minutes(1)))
    func passWithNoWaiterFreesTheTurn() async {
        // A turn left held would stop every later delivery or decode until the time limit.
        let turn = Turn()
        await turn.take()
        turn.pass()
        await turn.take()
        turn.pass()
    }
}
