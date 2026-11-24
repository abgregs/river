import AVFoundation
import Combine
import Foundation
import Testing
@testable import River

@Suite("AudioCaptureManager capture cycle")
struct AudioCaptureCycleTests {
    @MainActor
    @Test("a recording reaches the dictation as 16 kHz samples, every one of them, with its signal")
    func recordingDeliversEverySample() async throws {
        // A 100 ms buffer at 44.1 kHz is 1,600 samples at 16 kHz. The converter holds a few back
        // for the next buffer; stopping the recording delivers them, or each dictation would lose
        // its last milliseconds (planning 0039). A converter that emitted zeros of the right
        // length would pass a length check, so the 440 Hz sine must keep its energy too (a
        // 0.5-amplitude sine is about 0.35 RMS).
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        var samples: [Float] = []
        await manager.startRecording { samples += $0 }
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        try await manager.stopRecording()
        #expect(abs(samples.count - 1_600) <= 1)
        let rms = (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        #expect(rms > 0.1)
    }

    @MainActor
    @Test("stopRecording throws .noAudioCaptured when no buffer arrives within the warmup window")
    func stopRecordingThrowsWhenSilent() async {
        // Fail-loud rule (core-feature.md item 2): zero-length recording must
        // surface, never silently succeed. Test takes ~300 ms (the warmup wait).
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        await manager.startRecording()
        await #expect(throws: AudioCaptureError.self) {
            try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("a buffer that arrives late (within warmup) still produces samples")
    func lateBufferStillCaptures() async throws {
        // Engine-warmup race: a short tap that releases right when the engine
        // first produces audio. The wait inside stopRecording is what saves this
        // case. We model it by running stopRecording in a child Task and publishing
        // the buffer only once it is waiting: the yield below lets the task run on the
        // main actor up to its first poll, so without the wait it would already have
        // thrown `.noAudioCaptured`. The test sleeps for nothing, so a loaded runner
        // cannot push the buffer past the window (a real 100 ms sleep inside the shipped
        // 300 ms once failed this way in CI); the wait is long so the deadline stays out
        // of play, and it ends at the first buffer. stopRecordingThrowsWhenSilent covers
        // the shipped window expiring. The clock is frozen for the same reason: with
        // suites running in parallel the wall time has measured 1.8 s, which the
        // capture-gap check would report as lost audio. That check has its own suite;
        // this test is about the warmup wait.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { 100 })
        var samples: [Float] = []
        await manager.startRecording { samples += $0 }

        let stopTask = Task { @MainActor in
            try await manager.stopRecording(warmupWait: 10)
        }
        await Task.yield()
        microphone.publishForTest(makeSineBuffer(milliseconds: 50, frequency: 440, amplitude: 0.5))

        try await stopTask.value
        #expect(samples.count > 700)  // ~50 ms at 16 kHz ≈ 800 samples (margin keeps all)
        #expect(samples.count < 900)
    }
}

@Suite("AudioCaptureManager capture gap")
struct AudioCaptureGapTests {
    // Under `AVAudioEngine` the engine stopped on an audio device change and nothing told
    // the recording. The 2026-09-24 trace: a 14 s first recording with AirPods captured
    // 1.5 s and typed nothing, a quiet no-op. The capture unit now restarts on a device
    // change (MicrophoneCapability); when that fails, the shortfall must surface instead of a fragment passing as the dictation
    // (planning 0032). The bound is an absolute gap, so a long dictation cannot hide a
    // large loss behind its length. The clock is injected so no test waits out a recording.

    @MainActor
    @Test("a recording whose audio falls far short of its wall time throws .captureIncomplete")
    func shortfallThrows() async throws {
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock })

        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 1_500, frequency: 440, amplitude: 0.5))
        clock += 14                                   // 1.5 s of audio for a 14 s recording

        await #expect(throws: AudioCaptureError.self) {
            try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("a long recording missing a large share of its audio throws, whatever the share")
    func longShortfallThrows() async throws {
        // 2.5 min missing from a 5 min dictation: a ratio rule at 50% would let this
        // through as if half were enough. The gap rule does not.
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock })

        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 150_000, frequency: 440, amplitude: 0.5, sampleRate: 16_000))
        clock += 300

        await #expect(throws: AudioCaptureError.self) {
            try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("captureGapExceeded answers from the clock: false idle, false during a slow start, true once behind")
    func gapCheckFollowsTheClock() async throws {
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock })
        #expect(!manager.captureGapExceeded())            // nothing recording

        await manager.startRecording()
        clock += 2.0                                      // a slow engine start, longer than the gap bound
        #expect(!manager.captureGapExceeded())            // latency before the first buffer is not lost audio
        microphone.publishForTest(makeSineBuffer(milliseconds: 1_000, frequency: 440, amplitude: 0.5))
        clock += 1.0
        #expect(!manager.captureGapExceeded())            // audio kept up
        clock += 1.1                                      // then nothing arrived
        #expect(manager.captureGapExceeded())
        await manager.discardRecording()
    }

    @MainActor
    @Test("the watchdog calls onCaptureGapExceeded once the audio falls behind the clock")
    func watchdogFires() async throws {
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock }, watchdogInterval: 0.005)
        var fired = 0
        manager.onCaptureGapExceeded = { fired += 1 }

        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        for _ in 0..<10 { try await Task.sleep(nanoseconds: 2_000_000) }
        #expect(fired == 0)                               // no gap yet
        clock += 1.5                                      // no buffer for 1.5 s after the first
        for _ in 0..<50 where fired == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(fired == 1)

        await #expect(throws: AudioCaptureError.self) {   // and release reports it
            try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("a slow engine start longer than the gap bound does not trip the watchdog")
    func slowStartDoesNotFire() async throws {
        // Field data (2026-10-23): 0.91 s from the start call to the first buffer on a loaded
        // machine with AirPods, with nothing lost. Counting that as a gap would end a healthy
        // recording. The gap is measured from the first buffer instead.
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock }, watchdogInterval: 0.005)
        var fired = 0
        manager.onCaptureGapExceeded = { fired += 1 }
        var samples: [Float] = []

        await manager.startRecording { samples += $0 }
        clock += 2.0                                      // start-up slower than the 1 s gap bound
        for _ in 0..<10 { try await Task.sleep(nanoseconds: 2_000_000) }
        #expect(fired == 0)
        microphone.publishForTest(makeSineBuffer(milliseconds: 1_000, frequency: 440, amplitude: 0.5))
        clock += 1.0                                      // audio keeps up from the first buffer on
        for _ in 0..<10 { try await Task.sleep(nanoseconds: 2_000_000) }
        #expect(fired == 0)

        try await manager.stopRecording()                 // and release delivers the audio
        #expect(!samples.isEmpty)
    }

    @MainActor
    @Test("an engine that never delivers a buffer trips the watchdog at the start timeout")
    func deadEngineFiresAtStartTimeout() async throws {
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock }, watchdogInterval: 0.005)
        var fired = 0
        manager.onCaptureGapExceeded = { fired += 1 }

        await manager.startRecording()
        clock += Constants.captureStartTimeoutSeconds - 0.1
        for _ in 0..<10 { try await Task.sleep(nanoseconds: 2_000_000) }
        #expect(fired == 0)                               // still a slow start
        clock += 0.2                                      // now past the timeout, nothing heard
        for _ in 0..<50 where fired == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(fired == 1)

        do {
            try await manager.stopRecording(warmupWait: 0.01)
            Issue.record("expected .noAudioCaptured, got a recording")
        } catch AudioCaptureError.noAudioCaptured {
            // release reports the dead engine, not a gap
        } catch {
            Issue.record("expected .noAudioCaptured, got \(error)")
        }
    }

    @MainActor
    @Test("a recording whose audio tracks its wall time is delivered whole")
    func fullCoverageReturns() async throws {
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock })
        var samples: [Float] = []

        await manager.startRecording { samples += $0 }
        for _ in 0..<10 {
            microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        }
        clock += 1.2                                  // 1.0 s of audio, 1.2 s since the first buffer: in flight at release

        try await manager.stopRecording()
        #expect(samples.count > 15_000)
    }

    @MainActor
    @Test("a short tap passes when its audio trails the clock by less than the bound, even when that is most of it")
    func shortTapWarmupGapPasses() async throws {
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock })
        var samples: [Float] = []

        await manager.startRecording { samples += $0 }
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        clock += 0.9                                  // 0.1 s of audio for a 0.9 s tap

        try await manager.stopRecording()
        #expect(!samples.isEmpty)
    }
}

@Suite("AudioCaptureManager discard")
struct AudioCaptureDiscardTests {
    // The cancel path (planning 0017): discardRecording ends the recording and delivers
    // nothing more, where stopRecording finishes the conversion first.

    @MainActor
    @Test("discardRecording drops captured buffers so a later stop sees no audio")
    func discardDropsBuffers() async throws {
        // Capture a real (voiced) buffer, then discard. Re-arming a fresh recording
        // and stopping it with no new buffer must throw .noAudioCaptured — proof the
        // discarded recording was dropped, not carried into the next one.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)

        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        await manager.discardRecording()

        await manager.startRecording()  // fresh recording, no buffer published
        await #expect(throws: AudioCaptureError.self) {
            try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("discardRecording is safe when nothing was captured")
    func discardWithNothingCaptured() async {
        // Cancel can arrive before any buffer landed (a stray key-brush). Discard
        // must not throw or wait — it simply tears down and drops nothing.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        await manager.startRecording()
        await manager.discardRecording()  // no throw, no warmup wait
    }
}

@Suite("AudioCaptureManager sample-rate conversion")
struct AudioCaptureConvertTests {
    // The recording's one conversion (planning 0039): each buffer is resampled to 16 kHz as it
    // arrives, and each run of one format is finished when the format changes or the recording
    // stops.

    @MainActor
    @Test("a run converted buffer by buffer, then finished, gives every sample the run holds")
    func finishedRunGivesEverySample() throws {
        // 20 × 1,024 frames at 48 kHz is 6,826.7 samples at 16 kHz. Each buffer's conversion
        // holds a few back for the next; `finish` delivers them at the end of the run.
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let resampler = try #require(IncrementalResampler(from: format))
        var total = 0
        for _ in 0..<20 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
            buffer.frameLength = 1024
            for i in 0..<1024 { buffer.floatChannelData![0][i] = 0.3 }
            total += try resampler.convert(buffer).count
        }
        let held = try resampler.finish().count
        #expect(held > 0)
        #expect(abs(Double(total + held) - 20 * 1_024 / 3) < 1)
    }

    @MainActor
    @Test("each format run is converted at its own rate, and each is finished")
    func formatRunsConvertAtTheirOwnRates() async throws {
        // After the unit restarts on a device change, a recording holds 24 kHz AirPods buffers
        // and then 48 kHz built-in-microphone buffers (planning 0032). One converter built for
        // the first format would resample the second run at the wrong rate: 100 ms at 48 kHz read
        // as 24 kHz comes out as 200 ms. Each run converts at its own rate and is finished before
        // the next starts, so 100 ms + 100 ms is 3,200 samples at 16 kHz, with its energy.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { 100 })
        var samples: [Float] = []
        await manager.startRecording { samples += $0 }
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5, sampleRate: 24_000))
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5, sampleRate: 48_000))
        try await manager.stopRecording()

        #expect(abs(samples.count - 3_200) <= 2)
        let rms = (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        #expect(rms > 0.1)
    }

    @MainActor
    @Test("a format no converter can take makes no resampler")
    func unconvertibleFormatHasNoResampler() throws {
        // A zero-channel source has no conversion path to 16 kHz mono. `AudioCaptureManager`
        // reads a missing resampler as a failed conversion and throws `.conversionFailed` at
        // release, rather than passing off a recording with a hole in it as whole.
        let badFormat = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 0, interleaved: false))
        #expect(IncrementalResampler(from: badFormat) == nil)
    }
}

// Synthesize a silent 44.1 kHz mono Float32 buffer of the requested duration.
@MainActor
private func makeBuffer(milliseconds: Int, sampleRate: Double = 44_100) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
    )!
    let frames = AVAudioFrameCount(Double(milliseconds) * sampleRate / 1000.0)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    return buffer
}

// Synthesize a non-silent 44.1 kHz mono Float32 buffer holding a pure sine, so a
// conversion test can assert the output carries real energy (not zeros of the
// right length). Amplitude and frequency are fixed by the caller for a known RMS.
@MainActor
private func makeSineBuffer(
    milliseconds: Int, frequency: Double, amplitude: Float, sampleRate: Double = 44_100
) -> AVAudioPCMBuffer {
    let buffer = makeBuffer(milliseconds: milliseconds, sampleRate: sampleRate)
    let frames = Int(buffer.frameLength)
    let channel = buffer.floatChannelData![0]
    for i in 0..<frames {
        channel[i] = amplitude * Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
    }
    return buffer
}
