import AVFoundation
import Foundation
import Testing
@testable import River

@Suite("AudioCaptureManager ready mode")
struct AudioCaptureReadyModeTests {
    // Planning 0033: while the microphone is ready the unit runs between recordings and
    // a press starts from the last half second. The clock is injected and frozen unless a
    // test moves it, because the capture gap check (planning 0032) must keep measuring
    // only live audio: the seed is audio from before the press, not audio the unit owes.

    @MainActor
    @Test("a recording starts with the window's audio and the live audio that follows")
    func recordingStartsWithTheWindow() async throws {
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { 100 })
        await manager.setReady(true)
        #expect(microphone.isListening)

        for _ in 0..<10 { microphone.publishForTest(makeSineBuffer(milliseconds: 100)) }   // 1.0 s idle
        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100))                        // live
        let samples = try await manager.stopRecording()

        // 0.5 s of pre-roll to within one 100 ms buffer, plus 100 ms live, at 16 kHz: at
        // least 0.6 s and under 0.7 s. Without the seed this would be ~1,600 samples.
        #expect(samples.count > 9_400)
        #expect(samples.count < 11_400)
    }

    @MainActor
    @Test("seeded audio does not count toward the capture gap")
    func seedIsNotLiveAudio() async throws {
        var clock: TimeInterval = 100
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { clock })
        await manager.setReady(true)
        for _ in 0..<5 { microphone.publishForTest(makeSineBuffer(milliseconds: 100)) }

        await manager.startRecording()
        #expect(!manager.captureGapExceeded())
        // Live audio tracks the clock for 2 s. If the seed were counted as captured audio
        // the gap would read -0.5 s and a real 0.5 s hole would pass; if it moved the
        // first-buffer clock, a healthy recording would read 0.5 s behind.
        for _ in 0..<20 {
            clock += 0.1
            microphone.publishForTest(makeSineBuffer(milliseconds: 100))
        }
        #expect(!manager.captureGapExceeded())
        clock += 1.2                                      // then a real hole
        #expect(manager.captureGapExceeded())
        await #expect(throws: AudioCaptureError.self) {
            _ = try await manager.stopRecording()
        }
    }

    @MainActor
    @Test("a recording that received only the seed is no audio at all")
    func seedAloneIsNoAudio() async {
        // The pre-roll predates the press, so a dead unit must still surface as
        // .noAudioCaptured rather than typing half a second of room tone from before.
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { 100 })
        await manager.setReady(true)
        for _ in 0..<5 { microphone.publishForTest(makeSineBuffer(milliseconds: 100)) }

        await manager.startRecording()
        await #expect(throws: AudioCaptureError.self) {
            _ = try await manager.stopRecording(warmupWait: 0.01)
        }
    }

    @MainActor
    @Test("streaming receives the pre-roll before the live audio")
    func streamingSeesThePreRoll() async throws {
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { 100 })
        await manager.setReady(true)
        for _ in 0..<5 { microphone.publishForTest(makeSineBuffer(milliseconds: 100)) }

        var streamed = 0
        await manager.startRecording(onSamples: { streamed += $0.count })
        #expect(streamed > 7_500)                         // 0.5 s at 16 kHz, already there
        microphone.publishForTest(makeSineBuffer(milliseconds: 100))
        #expect(streamed > 9_000)
        _ = try await manager.stopRecording()
    }

    @MainActor
    @Test("stopping in ready mode leaves the unit running and the window refilling")
    func stopKeepsTheUnitRunning() async throws {
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { 100 })
        await manager.setReady(true)

        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100))
        _ = try await manager.stopRecording()
        #expect(microphone.isListening)

        for _ in 0..<3 { microphone.publishForTest(makeSineBuffer(milliseconds: 100)) }  // refills
        await manager.startRecording()
        microphone.publishForTest(makeSineBuffer(milliseconds: 100))
        let samples = try await manager.stopRecording()
        #expect(samples.count > 6_000)                    // 0.3 s seed + 0.1 s live
    }

    @MainActor
    @Test("ready mode off stops the unit at once while idle, and after the recording when recording")
    func readyOffStopsTheUnit() async throws {
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { 100 })
        await manager.setReady(true)
        #expect(microphone.isListening)
        await manager.setReady(false)
        #expect(!microphone.isListening)

        await manager.setReady(true)
        await manager.startRecording()
        await manager.setReady(false)                     // the switch flipped mid-recording
        #expect(microphone.isListening)                   // the recording keeps its unit
        microphone.publishForTest(makeSineBuffer(milliseconds: 100))
        _ = try await manager.stopRecording()
        #expect(!microphone.isListening)                  // applied at the recording's end
    }

    @MainActor
    @Test("with ready mode off a recording starts and stops the unit as before")
    func readyOffIsTheOldPath() async throws {
        let microphone = MicrophoneCapability()
        microphone.skipEngineForTesting = true
        let manager = AudioCaptureManager(microphone: microphone, now: { 100 })
        #expect(!microphone.isListening)
        await manager.startRecording()
        #expect(microphone.isListening)
        microphone.publishForTest(makeSineBuffer(milliseconds: 100))
        _ = try await manager.stopRecording()
        #expect(!microphone.isListening)
    }

    private func makeSineBuffer(milliseconds: Int, sampleRate: Double = 44_100) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let frames = AVAudioFrameCount(Double(milliseconds) * sampleRate / 1000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            channel[i] = 0.5 * Float(sin(2 * Double.pi * 440 * Double(i) / sampleRate))
        }
        return buffer
    }
}
