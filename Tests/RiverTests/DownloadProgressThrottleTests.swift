import Testing
@testable import River

@Suite("Download progress throttle")
struct DownloadProgressThrottleTests {
    // planning 0004: a loader's progress handler can run for every chunk of bytes, from any
    // queue. The ring and Settings need a fraction that only rises, at a pace worth drawing.

    @Test("only a rise of a whole step passes, so a handler called per chunk can't flood the main actor")
    func passesWholeSteps() {
        let throttle = DownloadProgressThrottle(step: 0.1)
        #expect(throttle.report(0) == 0)
        #expect(throttle.report(0.05) == nil)
        #expect(throttle.report(0.1) == 0.1)
        #expect(throttle.report(0.15) == nil)
    }

    @Test("the fraction never falls, so the arc never moves backwards")
    func neverFalls() {
        let throttle = DownloadProgressThrottle(step: 0.1)
        #expect(throttle.report(0.5) == 0.5)
        #expect(throttle.report(0.2) == nil)
        #expect(throttle.report(0.65) == 0.65)
    }

    @Test("the end of a download passes even less than a step after the last, and only once")
    func endPassesOnce() {
        // Without it, a download that ends between steps would stop short of full.
        let throttle = DownloadProgressThrottle(step: 0.1)
        #expect(throttle.report(0.95) == 0.95)
        #expect(throttle.report(1) == 1)
        #expect(throttle.report(1) == nil)
    }

    @Test("a download that turns to preparing says so once, and reports no fraction after")
    func preparingEndsTheDownload() {
        // FluidAudio compiles each model in turn, and reports each compile.
        let throttle = DownloadProgressThrottle(step: 0.1)
        #expect(throttle.report(0.3) == 0.3)
        #expect(throttle.markPreparing())
        #expect(!throttle.markPreparing())
        #expect(throttle.report(0.9) == nil)
    }
}
