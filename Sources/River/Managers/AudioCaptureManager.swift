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
    /// Buffers arrived, but they cover far less of the recording than its wall time:
    /// the engine stopped part-way (an audio device change it could not recover from)
    /// and the rest of the dictation was never heard. Surfaced rather than typing a
    /// fragment as if it were the whole.
    case captureIncomplete(capturedSeconds: Double, recordingSeconds: Double)

    var errorDescription: String? {
        switch self {
        case .noAudioCaptured:
            return "No audio was captured (engine may have failed to start)."
        case .conversionFailed:
            return "Could not convert recorded audio to 16 kHz mono."
        case .captureIncomplete(let captured, let recording):
            return String(format: "Only %.1f s of a %.1f s recording was captured (the audio device changed or stopped).", captured, recording)
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
    // Injectable clock so the gap check is tested without waiting out a real recording.
    private let now: () -> TimeInterval
    private var recordingStartedAt: TimeInterval?
    // When the first buffer arrived. The gap is measured from here, not from the start
    // call: the engine's start-up (0.9 s seen on a loaded machine with AirPods) is latency,
    // not lost audio, and counting it put a healthy recording within 0.1 s of the bound.
    private var firstBufferAt: TimeInterval?
    // Running total of the audio that arrived, in seconds at each buffer's own rate.
    private var capturedSeconds: Double = 0
    // The watchdog: every `watchdogInterval` it compares the clock since the first buffer
    // with `capturedSeconds` and, past `Constants.captureGapMaximumSeconds`, calls
    // `onCaptureGapExceeded` so the session ends the recording early. `stopRecording` then
    // throws as it would at release. Before the first buffer it instead waits out
    // `Constants.captureStartTimeoutSeconds`, so a dead engine still fails fast.
    private let watchdogInterval: Double
    private var watchdog: Task<Void, Never>?
    /// Called on the main actor when the recording's audio falls more than
    /// `Constants.captureGapMaximumSeconds` behind the clock. Set once by the session.
    var onCaptureGapExceeded: (@MainActor () -> Void)?

    /// Upper bound on the engine-warmup wait inside `stopRecording`. `AVAudioEngine`
    /// produces its first tap-callback buffer ~60-100 ms after `start()`; a short
    /// tap that releases inside that window would otherwise drop the utterance.
    /// See `architecture/river-pipeline.md` "Engine warmup".
    static let warmupWaitSeconds: Double = 0.3

    init(
        microphone: MicrophoneCapability,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        watchdogInterval: Double = Constants.captureWatchdogIntervalSeconds
    ) {
        self.microphone = microphone
        self.now = now
        self.watchdogInterval = watchdogInterval
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
        recordingStartedAt = now()
        firstBufferAt = nil
        capturedSeconds = 0
        microphone.audioBuffers
            .sink { [weak self] buffer in
                guard let self else { return }
                if firstBufferAt == nil { firstBufferAt = now() }
                buffers.append(buffer)
                capturedSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
                forwardLive(buffer)
            }
            .store(in: &cancellables)
        await microphone.startEngine()
        startWatchdog()
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let interval = watchdogInterval
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                if captureGapExceeded() {
                    logger.error("Capture gap exceeded \(Constants.captureGapMaximumSeconds, privacy: .public) s mid-recording; ending the recording")
                    onCaptureGapExceeded?()
                    return
                }
            }
        }
    }

    // internal for testability — the watchdog's question, answered from the injected
    // clock: has the audio fallen more than `captureGapMaximumSeconds` behind the clock
    // since it began arriving? Before the first buffer the only failure is an engine that
    // never starts, bounded by `captureStartTimeoutSeconds`.
    func captureGapExceeded() -> Bool {
        guard let recordingStartedAt else { return false }
        guard let firstBufferAt else {
            return now() - recordingStartedAt > Constants.captureStartTimeoutSeconds
        }
        return now() - firstBufferAt - capturedSeconds > Constants.captureGapMaximumSeconds
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
    ///
    /// `warmupWait` exists for tests: a loaded test machine can oversleep the 0.3 s window,
    /// so the late-buffer test passes a long one. The wait still ends at the first buffer.
    func stopRecording(warmupWait: Double = AudioCaptureManager.warmupWaitSeconds) async throws -> [Float] {
        watchdog?.cancel()
        watchdog = nil
        let deadline = Date().addingTimeInterval(warmupWait)
        while buffers.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        cancellables.removeAll()
        microphone.stopEngine()
        onSamples = nil
        resampler = nil

        guard !buffers.isEmpty else {
            logger.warning("stopRecording: no audio buffers arrived within \(warmupWait, privacy: .public)s")
            throw AudioCaptureError.noAudioCaptured
        }

        let collected = buffers
        buffers.removeAll(keepingCapacity: true)
        let recordingSeconds = recordingStartedAt.map { now() - $0 } ?? 0
        // Buffers arrived, so `firstBufferAt` is set; the fallbacks only satisfy the optional.
        let startupSeconds = (firstBufferAt ?? 0) - (recordingStartedAt ?? 0)
        let heardSeconds = firstBufferAt.map { now() - $0 } ?? 0
        recordingStartedAt = nil
        firstBufferAt = nil

        // The engine stops on a device change and restarts (MicrophoneCapability). If
        // the restart failed, the buffers stop short of the recording. Typing the
        // fragment would pass off part of the dictation as the whole. The gap is
        // counted from the first buffer: start-up latency is not missing audio.
        let capturedSeconds = self.capturedSeconds
        let gapSeconds = heardSeconds - capturedSeconds
        if gapSeconds > Constants.captureGapMaximumSeconds {
            logger.error("stopRecording: captured \(capturedSeconds, format: .fixed(precision: 2), privacy: .public) s of a \(recordingSeconds, format: .fixed(precision: 2), privacy: .public) s recording")
            throw AudioCaptureError.captureIncomplete(capturedSeconds: capturedSeconds, recordingSeconds: recordingSeconds)
        }

        let samples = try Self.convert(collected)
        let trimmed = Self.trimSilence(samples)
        let formats = Self.formatRuns(collected).map { "\(Int($0.format.sampleRate)) Hz" }.joined(separator: " -> ")
        logger.info("Captured \(samples.count, privacy: .public) samples (16 kHz mono) from \(collected.count, privacy: .public) buffers @ \(formats, privacy: .public) over \(recordingSeconds, format: .fixed(precision: 2), privacy: .public) s, startup \(startupSeconds, format: .fixed(precision: 2), privacy: .public) s, gap \(gapSeconds, format: .fixed(precision: 2), privacy: .public) s; \(trimmed.count, privacy: .public) after silence trim")
        return trimmed
    }

    /// Discards an in-flight recording (planning 0017): tears down the buffer
    /// subscription, stops the engine, and drops every captured buffer WITHOUT
    /// converting, trimming, or returning them. The cancel-path counterpart to
    /// `stopRecording` — there is no audio to transcribe or paste, so it neither
    /// waits for warmup nor throws `.noAudioCaptured` (an empty buffer list is the
    /// expected outcome, not a failure). Safe to call when nothing is recording.
    func discardRecording() async {
        watchdog?.cancel()
        watchdog = nil
        cancellables.removeAll()
        microphone.stopEngine()
        onSamples = nil
        resampler = nil
        recordingStartedAt = nil
        firstBufferAt = nil
        let dropped = buffers.count
        buffers.removeAll(keepingCapacity: true)
        logger.info("discardRecording: dropped \(dropped, privacy: .public) buffers; no transcription")
    }

    // internal for testability — converts a recording whose format may change part-way
    // (the engine restarted on a new device: 24 kHz AirPods, then the 48 kHz built-in
    // mic) to one continuous 16 kHz mono stream. Each run of same-format buffers gets
    // its own converter; one converter fed both would resample the second run at the
    // first run's rate.
    static func convert(_ buffers: [AVAudioPCMBuffer], toSampleRate: Double = 16_000) throws -> [Float] {
        var samples: [Float] = []
        for run in formatRuns(buffers) {
            samples += try convert(run.buffers, from: run.format, toSampleRate: toSampleRate)
        }
        return samples
    }

    // internal for testability — consecutive buffers grouped by format, in order.
    static func formatRuns(_ buffers: [AVAudioPCMBuffer]) -> [(format: AVAudioFormat, buffers: [AVAudioPCMBuffer])] {
        var runs: [(format: AVAudioFormat, buffers: [AVAudioPCMBuffer])] = []
        for buffer in buffers {
            if let last = runs.indices.last, runs[last].format == buffer.format {
                runs[last].buffers.append(buffer)
            } else {
                runs.append((buffer.format, [buffer]))
            }
        }
        return runs
    }

    // internal for testability — pure conversion from N same-format buffers
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
