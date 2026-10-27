import AVFoundation
import Testing
@testable import River

@Suite("PreRollWindow")
struct PreRollWindowTests {
    // The window is what a recording starts from (planning 0033, decision 2), so it must
    // hold the last `preRollSeconds` to within one buffer: a window that kept less would
    // clip the onset the feature exists to keep, and one that kept more would type audio
    // from before the user chose to dictate.

    @Test("keeps the most recent half second to within one buffer")
    func keepsTheWindow() {
        var window = PreRollWindow(seconds: 0.5)
        for _ in 0..<100 { window.append(makeBuffer(milliseconds: 11)) }   // 1.1 s in
        #expect(window.heldSeconds >= 0.5)
        #expect(window.heldSeconds < 0.5 + 0.011 + 0.0001)
        let drained = window.drain()
        #expect(drained.count == 46)                                       // 46 × 11 ms = 0.506 s
        #expect(window.isEmpty)
        #expect(window.heldSeconds == 0)
    }

    @Test("evicts by duration, not by count, across buffers of different sizes")
    func evictsByDuration() {
        var window = PreRollWindow(seconds: 0.5)
        window.append(makeBuffer(milliseconds: 400))
        window.append(makeBuffer(milliseconds: 400))   // 0.8 s: the first alone would leave 0.4 s, so both stay
        #expect(window.drain().count == 2)
        window.append(makeBuffer(milliseconds: 400))
        window.append(makeBuffer(milliseconds: 400))
        window.append(makeBuffer(milliseconds: 400))   // 1.2 s: dropping the first leaves 0.8 s, enough
        #expect(window.drain().count == 2)
    }

    @Test("a long idle keeps only the window and returns it oldest first")
    func longIdleStaysBounded() {
        var window = PreRollWindow(seconds: 0.5)
        var expectedOldest: AVAudioPCMBuffer?
        for index in 0..<5_000 {                                           // ~54 s of idle
            let buffer = makeBuffer(milliseconds: 11)
            if index == 5_000 - 46 { expectedOldest = buffer }
            window.append(buffer)
        }
        let drained = window.drain()
        #expect(drained.count == 46)
        #expect(drained.first === expectedOldest)
    }

    @Test("an empty window drains to nothing")
    func emptyDrains() {
        var window = PreRollWindow(seconds: 0.5)
        #expect(window.isEmpty)
        #expect(window.drain().isEmpty)
    }

    private func makeBuffer(milliseconds: Int, sampleRate: Double = 48_000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let frames = AVAudioFrameCount(Double(milliseconds) * sampleRate / 1000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        return buffer
    }
}
