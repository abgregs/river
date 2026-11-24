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
    /// `AVAudioConverter` couldn't be made for a buffer's format, or a conversion returned an error.
    case conversionFailed
    /// Buffers arrived, but they cover far less of the recording than its wall time:
    /// the engine stopped part-way (an audio device change it could not recover from)
    /// and the rest of the dictation was never heard. Surfaced rather than typing a
    /// fragment as if it were the whole.
    case captureIncomplete(capturedSeconds: Double, recordingSeconds: Double)

    var errorDescription: String? {
        switch self {
        case .noAudioCaptured:
            return "No audio was captured (the microphone may have failed to start)."
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

    // One standing subscription to the capability's buffers, installed on first use. The
    // sink routes each buffer by state: into the recording, into the pre-roll window
    // while the microphone is ready between recordings, or nowhere.
    private var subscription: AnyCancellable?
    private var isRecording = false
    // Whether the unit should run between recordings (planning 0033). The session
    // decides through `setReady`; this manager is the only caller of `startEngine` and
    // `stopEngine`, for recordings and for ready mode alike. A change that arrives during
    // a recording is applied when the recording ends, so it can never stop the unit
    // under the recording.
    private var ready = false
    private var window = PreRollWindow(seconds: Constants.preRollSeconds)
    // Audio seeded from the window at the press, for the log line only: it is kept out
    // of `capturedSeconds` and the first-buffer clock, which measure live capture.
    private var seededSeconds: Double = 0
    // The recording's one conversion (planning 0039): each buffer is resampled to 16 kHz mono
    // as it arrives and handed to `onSamples`, the dictation that decodes it. Each run of
    // same-format buffers has its own resampler, finished when the format changes and when the
    // recording stops, so the samples its filter holds back are delivered too.
    private var onSamples: @MainActor ([Float]) -> Void = { _ in }
    private var run: (format: AVAudioFormat, resampler: IncrementalResampler?)?
    // Set when a buffer couldn't be converted; `stopRecording` then throws `.conversionFailed`.
    private var conversionFailed = false
    // For the log line only: what the recording delivered, and the rate of each format run.
    private var bufferCount = 0
    private var sampleCount = 0
    private var runRates: [Int] = []
    // Injectable clock so the gap check is tested without waiting out a real recording.
    private let now: () -> TimeInterval
    private var recordingStartedAt: TimeInterval?
    // When the first live buffer arrived. The gap is measured from here, not from the start
    // call: the engine's start-up (0.9 s seen on a loaded machine with AirPods) is latency,
    // not lost audio, and counting it put a healthy recording within 0.1 s of the bound.
    private var firstBufferAt: TimeInterval?
    // Running total of the live audio that arrived, in seconds at each buffer's own rate.
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

    /// Upper bound on the wait inside `stopRecording` for the first live buffer. The
    /// capture unit's render callback first fires after `AudioOutputUnitStart` (0.07–0.09 s
    /// from a warm start, 0.19–0.21 s cold, measured 2026-10-26); a short tap that releases
    /// inside that window on the fallback path would otherwise drop the utterance. See
    /// `architecture/river-pipeline.md` "The ready microphone and the pre-roll".
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

    /// Keeps the capture unit running between recordings, or not (planning 0033). While
    /// idle the change applies at once: the unit starts and the pre-roll window fills, or
    /// the unit stops and the window is dropped. During a recording it applies when the
    /// recording ends.
    func setReady(_ ready: Bool) async {
        guard self.ready != ready else { return }
        self.ready = ready
        logger.info("Microphone ready mode \(ready ? "on" : "off", privacy: .public)")
        guard !isRecording else { return }
        await applyReadiness()
    }

    private func applyReadiness() async {
        if ready {
            subscribeIfNeeded()
            await microphone.startEngine()
        } else {
            _ = window.drain()
            microphone.stopEngine()
        }
    }

    private func subscribeIfNeeded() {
        guard subscription == nil else { return }
        subscription = microphone.audioBuffers.sink { [weak self] buffer in
            guard let self else { return }
            if isRecording {
                if firstBufferAt == nil { firstBufferAt = now() }
                capturedSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
                convert(buffer)
            } else if ready {
                window.append(buffer)
            }
        }
    }

    /// Starts a recording. When the unit is already running (ready mode) the recording
    /// is seeded with the pre-roll window, so it begins before the press. Otherwise the
    /// unit is started on the press, as before 0033, and the fallback is logged; a unit
    /// that is listening but not capturing (it failed to start, or its device vanished)
    /// is stopped first so `startEngine` rebuilds it. Idempotent while recording. Note:
    /// this never throws — the capability fails quietly (logged warning) if the unit
    /// can't start. `stopRecording` is the fail-loud surface (throws `.noAudioCaptured`
    /// if no live buffer arrived).
    ///
    /// `onSamples` receives the recording as 16 kHz mono samples: the pre-roll first, then
    /// each buffer as soon as it arrives, and the last few when `stopRecording` finishes the
    /// conversion. It is the recording's only copy at 16 kHz; this manager keeps none.
    func startRecording(onSamples: @escaping @MainActor ([Float]) -> Void = { _ in }) async {
        guard !isRecording else { return }
        self.onSamples = onSamples
        run = nil
        conversionFailed = false
        bufferCount = 0
        sampleCount = 0
        runRates = []
        firstBufferAt = nil
        capturedSeconds = 0
        seededSeconds = 0
        subscribeIfNeeded()
        if ready, microphone.isCapturing {
            let seed = window.drain()
            seededSeconds = seed.reduce(0) { $0 + Double($1.frameLength) / $1.format.sampleRate }
            for buffer in seed { convert(buffer) }
            isRecording = true
            recordingStartedAt = now()
        } else {
            if ready {
                logger.warning("Capture unit was not running at the press; starting it now")
            }
            _ = window.drain()
            isRecording = true
            recordingStartedAt = now()
            microphone.stopEngine()
            await microphone.startEngine()
        }
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

    // Resamples one buffer into the recording. A device change mid-recording changes the
    // format (24 kHz AirPods, then the 48 kHz built-in microphone): the run before it is
    // finished and a new resampler starts, since one converter fed both would resample the
    // second run at the first run's rate (planning 0032).
    private func convert(_ buffer: AVAudioPCMBuffer) {
        bufferCount += 1
        if run?.format != buffer.format {
            finishRun()
            let resampler = IncrementalResampler(from: buffer.format)
            if resampler == nil {
                conversionFailed = true
                logger.error("No converter from \(Int(buffer.format.sampleRate), privacy: .public) Hz, \(buffer.format.channelCount, privacy: .public) channels to 16 kHz mono")
            }
            run = (buffer.format, resampler)
            runRates.append(Int(buffer.format.sampleRate))
        }
        guard let resampler = run?.resampler else { return }
        do {
            deliver(try resampler.convert(buffer))
        } catch {
            conversionFailed = true
            logger.error("A buffer failed to convert to 16 kHz")
        }
    }

    // Delivers what the current run's resampler still holds, and ends the run.
    private func finishRun() {
        defer { run = nil }
        guard let resampler = run?.resampler else { return }
        do {
            deliver(try resampler.finish())
        } catch {
            conversionFailed = true
            logger.error("A format run failed to finish converting to 16 kHz")
        }
    }

    private func deliver(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        sampleCount += samples.count
        onSamples(samples)
    }

    /// Waits up to `warmupWaitSeconds` for the first live buffer (so short taps still
    /// produce audio), delivers the samples the conversion still holds, and ends the
    /// recording. The unit stops unless ready mode keeps it running. Throws
    /// `.noAudioCaptured` if the wait expired with no live buffer, whatever the pre-roll
    /// held: the pre-roll predates the press and is never typed on its own. The caller
    /// (RiverSession) surfaces this rather than letting a zero-length recording silently
    /// succeed. Throws `.captureIncomplete` when the audio stopped well short of the
    /// recording, and `.conversionFailed` when a buffer couldn't be converted. Samples
    /// delivered before a throw stay delivered: the session types what was heard, unless no
    /// live audio arrived.
    ///
    /// `warmupWait` exists for tests: a loaded test machine can oversleep the 0.3 s window,
    /// so the late-buffer test passes a long one. The wait still ends at the first buffer.
    func stopRecording(warmupWait: Double = AudioCaptureManager.warmupWaitSeconds) async throws {
        watchdog?.cancel()
        watchdog = nil
        let deadline = Date().addingTimeInterval(warmupWait)
        while firstBufferAt == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        finishRun()
        let recordingSeconds = recordingStartedAt.map { now() - $0 } ?? 0
        let startupSeconds = (firstBufferAt ?? 0) - (recordingStartedAt ?? 0)
        let heardSeconds = firstBufferAt.map { now() - $0 } ?? 0
        let heardLiveAudio = firstBufferAt != nil
        let preRollSeconds = seededSeconds
        let conversionFailed = self.conversionFailed
        recordingStartedAt = nil
        firstBufferAt = nil
        seededSeconds = 0
        endRecording()

        guard heardLiveAudio else {
            logger.warning("stopRecording: no audio buffers arrived within \(warmupWait, privacy: .public)s")
            throw AudioCaptureError.noAudioCaptured
        }

        // The capture unit restarts when its selected device changes (MicrophoneCapability).
        // If the restart failed, or the pinned device stopped delivering, the buffers
        // stop short of the recording. Typing the
        // fragment would pass off part of the dictation as the whole. The gap is
        // counted from the first buffer: start-up latency is not missing audio.
        let capturedSeconds = self.capturedSeconds
        let gapSeconds = heardSeconds - capturedSeconds
        if gapSeconds > Constants.captureGapMaximumSeconds {
            logger.error("stopRecording: captured \(capturedSeconds, format: .fixed(precision: 2), privacy: .public) s of a \(recordingSeconds, format: .fixed(precision: 2), privacy: .public) s recording")
            throw AudioCaptureError.captureIncomplete(capturedSeconds: capturedSeconds, recordingSeconds: recordingSeconds)
        }
        guard !conversionFailed else {
            logger.error("stopRecording: part of the recording couldn't be converted to 16 kHz")
            throw AudioCaptureError.conversionFailed
        }

        let rates = runRates.map { "\($0) Hz" }.joined(separator: " -> ")
        logger.info("Captured \(self.sampleCount, privacy: .public) samples (16 kHz mono) from \(self.bufferCount, privacy: .public) buffers @ \(rates, privacy: .public) over \(recordingSeconds, format: .fixed(precision: 2), privacy: .public) s, pre-roll \(preRollSeconds, format: .fixed(precision: 2), privacy: .public) s, startup \(startupSeconds, format: .fixed(precision: 2), privacy: .public) s, gap \(gapSeconds, format: .fixed(precision: 2), privacy: .public) s")
    }

    /// Discards an in-flight recording (planning 0017): ends the recording and stops its
    /// conversion, delivering nothing more. The cancel-path counterpart to `stopRecording`:
    /// there is no audio to transcribe or paste, so it neither waits for warmup nor throws
    /// `.noAudioCaptured` (no buffer at all is the expected outcome, not a failure). The
    /// session cancels the dictation the samples went to. Safe to call when nothing is
    /// recording.
    func discardRecording() async {
        watchdog?.cancel()
        watchdog = nil
        recordingStartedAt = nil
        firstBufferAt = nil
        seededSeconds = 0
        let dropped = bufferCount
        endRecording()
        logger.info("discardRecording: dropped \(dropped, privacy: .public) buffers; no transcription")
    }

    // The recording's end for the unit's lifetime: in ready mode the unit keeps running
    // and the sink refills the window from the next buffer; otherwise it stops as it
    // always did. This is also where a readiness change made during the recording lands.
    private func endRecording() {
        isRecording = false
        onSamples = { _ in }
        run = nil
        if !ready {
            microphone.stopEngine()
        }
    }
}

/// Resamples one run of same-format buffers to 16 kHz mono, a buffer at a time, keeping the
/// converter's state between buffers so the output is continuous; `finish()` delivers what
/// the converter's filter still holds once the run's last buffer is in. Together, they give
/// the same samples as converting the whole run at once. A recording's only conversion
/// (`AudioCaptureManager`, planning 0039), done on the main actor as each buffer arrives,
/// never inside the capture unit's render callback.
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

    /// `buffer` at 16 kHz, less the few samples the filter holds for the next call.
    func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate) + 64)
        var supplied = false
        // `.noDataNow` after the one buffer keeps the converter open for the next call;
        // `.endOfStream` would flush and close it.
        return try drain(capacity: capacity) { _, statusOut in
            if supplied {
                statusOut.pointee = .noDataNow
                return nil
            }
            supplied = true
            statusOut.pointee = .haveData
            return buffer
        }
    }

    /// The samples the filter still holds, once the run's last buffer is in. The resampler
    /// takes no buffer after this.
    func finish() throws -> [Float] {
        try drain(capacity: 1_024) { _, statusOut in
            statusOut.pointee = .endOfStream
            return nil
        }
    }

    // Runs the converter until it has nothing more to give for this input.
    private func drain(capacity: AVAudioFrameCount, input: @escaping AVAudioConverterInputBlock) throws -> [Float] {
        var samples: [Float] = []
        while let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) {
            var error: NSError?
            let status = converter.convert(to: output, error: &error, withInputFrom: input)
            if error != nil || status == .error { throw AudioCaptureError.conversionFailed }
            let frames = Int(output.frameLength)
            if frames > 0, let channel = output.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
            }
            if status != .haveData || frames == 0 { break }
        }
        return samples
    }
}
