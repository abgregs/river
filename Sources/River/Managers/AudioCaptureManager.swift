import AVFoundation
import Combine
import Foundation
import os

enum AudioCaptureError: Error, LocalizedError {
    /// `stopRecording` returned without ever seeing a buffer (engine never
    /// warmed up or the tap silently delivered none). Surfaced loudly per
    /// `requirements/core-feature.md` item 2 — short taps must not silently
    /// produce a zero-length recording.
    case noAudioCaptured
    /// `AVAudioConverter` initialization or `convert` returned an error.
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .noAudioCaptured:
            return "No audio was captured (engine may have failed to start)."
        case .conversionFailed:
            return "Could not convert recorded audio to 16 kHz mono."
        }
    }
}

@MainActor
final class AudioCaptureManager {
    private let microphone: MicrophoneCapability
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "audio")

    private var buffers: [AVAudioPCMBuffer] = []
    private var cancellables = Set<AnyCancellable>()
    // Live 16 kHz feed for streaming (0025 prototype): each buffer is also resampled as it
    // arrives and handed to `onSamples`. The batch conversion at stop time is unchanged.
    private var onSamples: (@MainActor ([Float]) -> Void)?
    private var resampler: IncrementalResampler?

    /// Upper bound on the engine-warmup wait inside `stopRecording`. `AVAudioEngine`
    /// produces its first tap-callback buffer ~60-100 ms after `start()`; a short
    /// tap that releases inside that window would otherwise drop the utterance.
    /// See `architecture/river-pipeline.md` "Engine warmup".
    static let warmupWaitSeconds: Double = 0.3

    init(microphone: MicrophoneCapability) {
        self.microphone = microphone
    }

    /// Subscribes to the capability's buffer stream and starts the engine.
    /// Idempotent on the subscription side; the capability's `startEngine` is
    /// itself idempotent. Note: this never throws — the capability fails quietly
    /// (logged warning) if the engine can't start. `stopRecording` is the
    /// fail-loud surface (throws `.noAudioCaptured` if no buffers arrived).
    ///
    /// `onSamples`, when given, receives each buffer as 16 kHz mono samples as soon as it
    /// arrives, for transcribing while the user speaks.
    func startRecording(onSamples: (@MainActor ([Float]) -> Void)? = nil) async {
        guard cancellables.isEmpty else { return }
        buffers.removeAll(keepingCapacity: true)
        self.onSamples = onSamples
        resampler = nil
        microphone.audioBuffers
            .sink { [weak self] buffer in
                self?.buffers.append(buffer)
                self?.forwardLive(buffer)
            }
            .store(in: &cancellables)
        await microphone.startEngine()
    }

    private func forwardLive(_ buffer: AVAudioPCMBuffer) {
        guard let onSamples else { return }
        // A device switch mid-recording changes the format; start a new converter for it.
        if resampler?.sourceFormat != buffer.format {
            resampler = IncrementalResampler(from: buffer.format)
        }
        guard let samples = resampler?.convert(buffer), !samples.isEmpty else { return }
        onSamples(samples)
    }

    /// Waits up to `warmupWaitSeconds` for the first buffer (so short taps still
    /// produce audio), then tears down the subscription, stops the engine,
    /// converts the accumulated buffers to 16 kHz mono Float32, and trims leading/
    /// trailing silence. Throws `.noAudioCaptured` if the wait expired with no
    /// buffers — the caller (RiverSession) surfaces this rather than letting a
    /// zero-length recording silently succeed. Returns `[]` when buffers arrived
    /// but the trim removed everything (an all-silence recording): the caller
    /// reads that as "nothing was said," not a failure (planning 0023).
    func stopRecording() async throws -> [Float] {
        let deadline = Date().addingTimeInterval(Self.warmupWaitSeconds)
        while buffers.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        cancellables.removeAll()
        microphone.stopEngine()
        onSamples = nil
        resampler = nil

        guard let firstBuffer = buffers.first else {
            logger.warning("stopRecording: no audio buffers arrived within \(Self.warmupWaitSeconds, privacy: .public)s")
            throw AudioCaptureError.noAudioCaptured
        }

        let sourceFormat = firstBuffer.format
        let collected = buffers
        buffers.removeAll(keepingCapacity: true)

        let samples = try Self.convert(collected, from: sourceFormat)
        let trimmed = Self.trimSilence(samples)
        logger.info("Captured \(samples.count, privacy: .public) samples (16 kHz mono) from \(collected.count, privacy: .public) buffers @ \(sourceFormat.sampleRate, privacy: .public) Hz; \(trimmed.count, privacy: .public) after silence trim")
        return trimmed
    }

    /// Discards an in-flight recording (planning 0017): tears down the buffer
    /// subscription, stops the engine, and drops every captured buffer WITHOUT
    /// converting, trimming, or returning them. The cancel-path counterpart to
    /// `stopRecording` — there is no audio to transcribe or paste, so it neither
    /// waits for warmup nor throws `.noAudioCaptured` (an empty buffer list is the
    /// expected outcome, not a failure). Safe to call when nothing is recording.
    func discardRecording() async {
        cancellables.removeAll()
        microphone.stopEngine()
        onSamples = nil
        resampler = nil
        let dropped = buffers.count
        buffers.removeAll(keepingCapacity: true)
        logger.info("discardRecording: dropped \(dropped, privacy: .public) buffers; no transcription")
    }

    // internal for testability — pure conversion from N hardware-format buffers
    // to a single 16 kHz mono Float32 sample array. Done once at stop time
    // rather than inside the tap callback (river-pipeline.md step 3).
    static func convert(
        _ buffers: [AVAudioPCMBuffer],
        from sourceFormat: AVAudioFormat,
        toSampleRate: Double = 16_000
    ) throws -> [Float] {
        guard !buffers.isEmpty else { return [] }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: toSampleRate,
            channels: 1,
            interleaved: false
        ) else { throw AudioCaptureError.conversionFailed }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioCaptureError.conversionFailed
        }

        let inputFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        // Conservative capacity: input × rate ratio + headroom for resampler latency.
        let outputCapacity = AVAudioFrameCount(
            ceil(Double(inputFrames) * (toSampleRate / sourceFormat.sampleRate)) + 1024
        )

        var feedIndex = 0
        let inputBlock: AVAudioConverterInputBlock = { _, statusOut in
            guard feedIndex < buffers.count else {
                statusOut.pointee = .endOfStream
                return nil
            }
            statusOut.pointee = .haveData
            let buffer = buffers[feedIndex]
            feedIndex += 1
            return buffer
        }

        var samples: [Float] = []
        samples.reserveCapacity(Int(outputCapacity))

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
                throw AudioCaptureError.conversionFailed
            }
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            if error != nil { throw AudioCaptureError.conversionFailed }
            let frames = Int(outputBuffer.frameLength)
            if frames > 0, let channelData = outputBuffer.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))
            }
            if status == .endOfStream || status == .inputRanDry || status == .error || frames == 0 {
                break
            }
        }

        return samples
    }

    // internal for testability — leading/trailing silence trim on the converted
    // 16 kHz mono buffer. Whisper's worst failure mode is inventing text
    // ("Thank you for watching.") from silent audio: an accidental activation
    // captures pure silence, and every real utterance carries trailing breath.
    // Drop quiet RMS windows at both ends, keeping `leadSeconds` before detected speech
    // and `tailSeconds` after it, so a word's soft onset survives. The gate is
    // `energyThreshold` for normal speech and drops toward `floor` for a quiet
    // recording, tracking its loudest window, so a whispered dictation is kept rather
    // than discarded whole. All-silence in → [] out, which the session reads as
    // "nothing was said" (planning 0023). Pure; runs at stop time on the `convert` output.
    static func trimSilence(
        _ samples: [Float],
        sampleRate: Double = 16_000,
        energyThreshold: Float = Constants.silenceTrimEnergyThreshold,
        peakRatio: Float = Constants.silenceTrimPeakRatio,
        floor: Float = Constants.silenceTrimFloor,
        leadSeconds: Double = Constants.silenceTrimLeadSeconds,
        tailSeconds: Double = Constants.silenceTrimTailSeconds
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let window = max(1, Int(sampleRate * 0.02))  // 20 ms RMS window
        let windows = stride(from: 0, to: samples.count, by: window).map { start in
            let end = min(start + window, samples.count)
            var sumSquares: Float = 0
            for i in start..<end { sumSquares += samples[i] * samples[i] }
            return (start: start, end: end, rms: (sumSquares / Float(end - start)).squareRoot())
        }
        let peak = windows.map(\.rms).max() ?? 0
        let threshold = max(floor, min(energyThreshold, peak * peakRatio))
        let voiced = windows.filter { $0.rms >= threshold }
        guard let first = voiced.first?.start, let last = voiced.last?.end else { return [] }
        let lower = max(0, first - Int(sampleRate * leadSeconds))
        let upper = min(samples.count, last + Int(sampleRate * tailSeconds))
        return Array(samples[lower..<upper])
    }
}

/// Resamples a recording to 16 kHz mono one buffer at a time, keeping the converter's state
/// between buffers so the output is continuous. The live counterpart of
/// `AudioCaptureManager.convert`, which converts the whole recording at once at stop time.
final class IncrementalResampler {
    let sourceFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from sourceFormat: AVAudioFormat, toSampleRate: Double = 16_000) {
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: toSampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return nil }
        self.sourceFormat = sourceFormat
        self.targetFormat = targetFormat
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate) + 64)
        var supplied = false
        var samples: [Float] = []
        while let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) {
            var error: NSError?
            // `.noDataNow` after the one buffer keeps the converter open for the next call;
            // `.endOfStream` would flush and close it.
            let status = converter.convert(to: output, error: &error) { _, statusOut in
                if supplied {
                    statusOut.pointee = .noDataNow
                    return nil
                }
                supplied = true
                statusOut.pointee = .haveData
                return buffer
            }
            if error != nil { return samples }
            let frames = Int(output.frameLength)
            if frames > 0, let channel = output.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
            }
            if status != .haveData || frames == 0 { break }
        }
        return samples
    }
}
