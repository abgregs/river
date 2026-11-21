import os

/// Keeps a download's fraction rising and passes on only the steps worth drawing (planning
/// 0004). A loader's progress handler can run for every chunk of bytes, on any queue, so the
/// throttle holds its state behind a lock and the main actor hears a few hundred updates at
/// most, never one that goes backwards.
final class DownloadProgressThrottle: Sendable {
    private struct State {
        var best = 0.0
        var passed = -1.0
        var preparing = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let step: Double

    init(step: Double = Constants.downloadProgressStep) { self.step = step }

    /// The fraction to pass on, or `nil` when it hasn't risen by a step since the last one
    /// passed on, or the download has turned to preparing. The end of a download always
    /// passes, once.
    func report(_ fraction: Double) -> Double? {
        let step = step
        return state.withLock { state in
            guard !state.preparing else { return nil }
            let value = min(max(fraction, state.best), 1)
            state.best = value
            guard value - state.passed >= step || (value >= 1 && state.passed < 1) else { return nil }
            state.passed = value
            return value
        }
    }

    /// `true` the first time only: a download that turns to preparing says so once.
    func markPreparing() -> Bool {
        state.withLock { state in
            defer { state.preparing = true }
            return !state.preparing
        }
    }
}
