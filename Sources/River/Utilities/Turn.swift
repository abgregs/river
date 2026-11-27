/// One caller at a time, in the order they asked (planning 0039): a caller takes the turn, does
/// its work, and passes it on. A delivery types and a decode runs only while it holds its turn.
@MainActor
final class Turn {
    private var isTaken = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Waits until the turn is free, then holds it. Not cancellable: a caller that stopped
    /// waiting would run out of turn.
    func take() async {
        guard isTaken else {
            isTaken = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the turn straight to the next caller in line, so none can cut in.
    func pass() {
        if waiting.isEmpty { isTaken = false } else { waiting.removeFirst().resume() }
    }
}
