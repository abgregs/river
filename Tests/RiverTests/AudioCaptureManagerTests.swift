import AVFoundation
import Combine
import Foundation
import Testing
@testable import River

@Suite("AudioCaptureManager capture cycle")
struct AudioCaptureCycleTests {
    @MainActor
    @Test("stopRecording returns 16 kHz samples when a buffer was published")
    func stopRecordingReturnsSamples() async throws {
        // Happy path: a single 100 ms buffer at 44.1 kHz → ~1600 samples at 16 kHz.
        // A *voiced* buffer — stopRecording now trims silence, so a zero buffer
        // would trim to empty (see AudioCaptureSilenceTrimTests).
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        let samples = try await manager.stopRecording()
        #expect(samples.count > 1500)
        #expect(samples.count < 1700)
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
            _ = try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("a buffer that arrives late (within warmup) still produces samples")
    func lateBufferStillCaptures() async throws {
        // Engine-warmup race: a short tap that releases right when the engine
        // first produces audio. The wait inside stopRecording is what saves this
        // case. We model it by running stopRecording in a child Task and publishing
        // the buffer from the test's own timeline. The wait is long here because the
        // shipped 300 ms is wall-clock time: a loaded CI runner oversleeping the
        // 100 ms below by 200 ms failed this test with `.noAudioCaptured`. The wait
        // ends at the first buffer, so the test still takes about 100 ms;
        // stopRecordingThrowsWhenSilent covers the shipped window expiring.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)
        await manager.startRecording()

        let stopTask = Task { @MainActor in
            try await manager.stopRecording(warmupWait: 10)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        // Voiced buffer: stopRecording trims silence, so zeros would trim to empty.
        microphone.publishForTest(makeSineBuffer(milliseconds: 50, frequency: 440, amplitude: 0.5))

        let samples = try await stopTask.value
        #expect(samples.count > 700)  // ~50 ms at 16 kHz ≈ 800 samples (margin keeps all)
        #expect(samples.count < 900)
    }
}

@Suite("AudioCaptureManager capture gap")
struct AudioCaptureGapTests {
    // The engine stops on an audio device change and nothing tells the recording. The
    // 2026-09-24 trace: a 14 s first recording with AirPods captured 1.5 s and typed
    // nothing, a quiet no-op. The engine now restarts (MicrophoneCapability); when that
    // fails, the shortfall must surface instead of a fragment passing as the dictation
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
            _ = try await manager.stopRecording()
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
            _ = try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("a recording whose audio tracks its wall time is returned")
    func fullCoverageReturns() async throws {
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock })

        await manager.startRecording()
        for _ in 0..<10 {
            microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        }
        clock += 1.2                                  // 1.0 s of audio for a 1.2 s recording: engine warmup

        let samples = try await manager.stopRecording()
        #expect(samples.count > 15_000)
    }

    @MainActor
    @Test("a short tap passes with a normal warmup gap, even when that gap is most of it")
    func shortTapWarmupGapPasses() async throws {
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock })

        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        clock += 0.9                                  // 0.1 s of audio for a 0.9 s tap

        let samples = try await manager.stopRecording()
        #expect(!samples.isEmpty)
    }
}

@Suite("AudioCaptureManager discard")
struct AudioCaptureDiscardTests {
    // The cancel path (planning 0017): discardRecording drops captured buffers and
    // stops the engine WITHOUT converting or returning them — the counterpart to
    // stopRecording's convert-and-return.

    @MainActor
    @Test("discardRecording drops captured buffers so a later stop sees no audio")
    func discardDropsBuffers() async throws {
        // Capture a real (voiced) buffer, then discard. Re-arming a fresh recording
        // and stopping it with no new buffer must throw .noAudioCaptured — proof the
        // discarded buffers were dropped, not carried into the next recording.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone)

        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5))
        await manager.discardRecording()

        await manager.startRecording()  // fresh recording, no buffer published
        await #expect(throws: AudioCaptureError.self) {
            _ = try await manager.stopRecording()
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
    @MainActor
    @Test("convert([]) returns an empty sample array")
    func convertEmpty() throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false
        )!
        let samples = try AudioCaptureManager.convert([], from: format)
        #expect(samples.isEmpty)
    }

    @MainActor
    @Test("convert downsamples 44.1 kHz mono Float32 to 16 kHz at the expected length")
    func convertDownsamples() throws {
        // 4410 frames @ 44.1 kHz = 100 ms → ~1600 frames @ 16 kHz. AVAudioConverter
        // has resampler latency, so we allow some tolerance instead of an exact match.
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false
        )!
        let samples = try AudioCaptureManager.convert([makeBuffer(milliseconds: 100)], from: format)
        #expect(samples.count > 1500)
        #expect(samples.count < 1700)
    }

    @MainActor
    @Test("convert throws .conversionFailed when no converter can be built for the source format")
    func convertThrowsWhenConverterUnbuildable() throws {
        // The `.conversionFailed` guard: a zero-channel source format has no valid
        // conversion path to 16 kHz mono, so `AVAudioConverter(from:to:)` returns
        // nil. Buffers are non-empty (so the early empty-return doesn't mask this),
        // but decoding never starts. Without this branch a converter failure would
        // surface as a crash or a silent empty result instead of `.noAudioCaptured`'s
        // sibling error the session can report.
        let badFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 0, interleaved: false
        )!
        #expect(throws: AudioCaptureError.self) {
            _ = try AudioCaptureManager.convert([makeBuffer(milliseconds: 100)], from: badFormat)
        }
    }

    @MainActor
    @Test("convert joins runs of different formats into one continuous 16 kHz stream")
    func convertJoinsFormatRuns() throws {
        // After the engine restarts on a device change, a recording holds 24 kHz AirPods
        // buffers and then 48 kHz built-in-mic buffers (planning 0032). One converter
        // built for the first format would resample the second run at the wrong rate:
        // 100 ms at 48 kHz read as 24 kHz comes out as 200 ms. Each run must convert
        // at its own rate, so 100 ms + 100 ms is ~200 ms at 16 kHz, with its energy.
        let airPods = makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5, sampleRate: 24_000)
        let builtIn = makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5, sampleRate: 48_000)

        let samples = try AudioCaptureManager.convert([airPods, builtIn])

        #expect(samples.count > 3_000)   // ~3200, less resampler latency per run
        #expect(samples.count < 3_400)
        let rms = (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        #expect(rms > 0.1)
        #expect(AudioCaptureManager.formatRuns([airPods, builtIn, builtIn]).map(\.buffers.count) == [1, 2])
    }

    @MainActor
    @Test("convert preserves signal energy, not just length, for a non-silent input")
    func convertPreservesSignalEnergy() throws {
        // The length tests feed silent zero buffers, so a converter that emitted
        // zeros of the right length would pass them. Feed a real 440 Hz sine and
        // assert the 16 kHz output carries energy (RMS well above zero) — proof the
        // samples are actually resampled, not blanked. Energy/shape, not sample
        // equality: AVAudioConverter latency makes exact-match brittle.
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false
        )!
        let samples = try AudioCaptureManager.convert(
            [makeSineBuffer(milliseconds: 100, frequency: 440, amplitude: 0.5)], from: format
        )
        #expect(samples.count > 1500)   // same resampler-latency window as the silent case
        #expect(samples.count < 1700)
        let rms = (samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        #expect(rms > 0.1)              // a 0.5-amplitude sine is ~0.35 RMS; zeros would be 0
    }
}

@Suite("AudioCaptureManager silence trim")
struct AudioCaptureSilenceTrimTests {
    // Whisper hallucinates text from silence — pasting words the user never spoke
    // is this app's worst failure. `trimSilence` drops below-threshold audio at
    // both ends of the 16 kHz buffer, keeping a margin so speech is never clipped.
    // Same synthetic-input pattern as the convert tests. See planning 0023.

    @MainActor
    @Test("all-silence input trims to empty")
    func allSilenceTrimsToEmpty() {
        // An accidental activation captures pure silence. It must trim to empty so
        // the session skips decode entirely — no hallucinated paste.
        let silence = [Float](repeating: 0, count: 16_000)  // 1 s of digital silence
        #expect(AudioCaptureManager.trimSilence(silence).isEmpty)
    }

    @MainActor
    @Test("empty input trims to empty")
    func emptyTrimsToEmpty() {
        #expect(AudioCaptureManager.trimSilence([]).isEmpty)
    }

    @MainActor
    @Test("silence-padded speech keeps the speech with a margin, dropping the padding")
    func paddedSpeechPreservesSpeech() {
        // 1 s silence, 0.5 s voiced, 1 s silence at 16 kHz. The silence beyond the
        // lead-in and tail margins must be dropped, but the speech and its margins
        // must survive intact.
        let pad = [Float](repeating: 0, count: 16_000)
        let speech = sineSamples(count: 8_000, frequency: 440, amplitude: 0.5)
        let padded = pad + speech + pad

        let out = AudioCaptureManager.trimSilence(padded)

        #expect(out.count < padded.count)           // padding trimmed
        #expect(out.count >= speech.count)          // speech + margins survive
        #expect(out.count < padded.count - 16_000)  // most of the silence is gone
        let rms = (out.reduce(Float(0)) { $0 + $1 * $1 } / Float(out.count)).squareRoot()
        #expect(rms > 0.1)                         // preserved speech carries energy
    }

    @MainActor
    @Test("speech-only input is returned untouched")
    func speechOnlyUntouched() {
        // No silence to trim: every window is voiced, so the whole buffer survives
        // (the margin clamps to the array bounds). Length is unchanged.
        let speech = sineSamples(count: 16_000, frequency: 440, amplitude: 0.5)
        #expect(AudioCaptureManager.trimSilence(speech).count == speech.count)
    }

    // The maintainer's smoke: quiet talking on a built-in mic never reached transcription
    // under the fixed -40 dBFS gate, so nothing was typed.
    @MainActor
    @Test("a quiet dictation survives the trim instead of being discarded whole")
    func quietDictationSurvives() {
        let pad = [Float](repeating: 0, count: 8_000)
        let quiet = sineSamples(count: 8_000, frequency: 440, amplitude: sineAmplitude(decibels: -44))
        let padded = pad + quiet + pad
        let fixedGate = AudioCaptureManager.trimSilence(padded, peakRatio: 1, floor: Constants.silenceTrimEnergyThreshold)
        #expect(fixedGate.isEmpty)
        #expect(AudioCaptureManager.trimSilence(padded).count >= quiet.count)
    }

    // Planning 0023: room tone left after speech can decode as invented text, so a normal
    // dictation's tail must be cut exactly where the fixed gate cut it.
    @MainActor
    @Test("normal speech keeps the fixed gate, so its quiet tail is still cut")
    func normalSpeechTrimsAsBefore() {
        let speech = sineSamples(count: 8_000, frequency: 440, amplitude: 0.5)
        let tail = sineSamples(count: 16_000, frequency: 440, amplitude: sineAmplitude(decibels: -45))
        let recording = speech + tail
        let trimmed = AudioCaptureManager.trimSilence(recording)
        #expect(trimmed == AudioCaptureManager.trimSilence(recording, peakRatio: 1, floor: Constants.silenceTrimEnergyThreshold))
        #expect(trimmed.count < speech.count + tail.count / 2)
    }

    // The maintainer's smoke (2026-09-26): with 0.1 s kept before a word, quick taps of
    // "hello there" reached Whisper clipped mid-word and decoded to nothing; the lead-in
    // is the context it needs. The tail stays short, since room tone after speech is what
    // Whisper turns into invented text (planning 0023).
    @MainActor
    @Test("the trim keeps half a second before speech and a fifth of a second after")
    func trimKeepsLeadInAndShortTail() {
        let silence = [Float](repeating: 0, count: 16_000)
        let speech = sineSamples(count: 8_000, frequency: 440, amplitude: 0.5)
        let out = AudioCaptureManager.trimSilence(silence + speech + silence)
        #expect(Constants.silenceTrimLeadSeconds == 0.5)
        #expect(Constants.silenceTrimTailSeconds == 0.2)
        #expect(out.count == Int(Constants.silenceTrimLeadSeconds * 16_000) + speech.count + Int(Constants.silenceTrimTailSeconds * 16_000))
    }

    // An accidental activation in a quiet room must still decode nothing.
    @MainActor
    @Test("near-silence below the floor still trims to empty")
    func nearSilenceTrimsToEmpty() {
        let roomTone = sineSamples(count: 16_000, frequency: 440, amplitude: sineAmplitude(decibels: -56))
        #expect(AudioCaptureManager.trimSilence(roomTone).isEmpty)
    }
}

// Peak amplitude of a sine whose RMS is this many decibels of full scale.
private func sineAmplitude(decibels: Double) -> Float {
    Float(pow(10, decibels / 20) * 2.0.squareRoot())
}

// A 16 kHz mono Float32 sample array holding a pure sine — a synthetic "speech"
// signal with known energy for the trim tests (mirrors makeSineBuffer, but as a
// bare sample array since trimSilence operates on the converted buffer).
private func sineSamples(
    count: Int, frequency: Double, amplitude: Float, sampleRate: Double = 16_000
) -> [Float] {
    (0..<count).map { amplitude * Float(sin(2.0 * .pi * frequency * Double($0) / sampleRate)) }
}

// Synthesize a silent 44.1 kHz mono Float32 buffer of the requested duration.
// Zeros are sufficient for length/conversion tests; M6 will exercise real audio.
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
