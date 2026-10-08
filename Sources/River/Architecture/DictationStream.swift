import Foundation
import os

/// One dictation transcribed while it is being spoken (0025 streaming prototype). Owned by
/// `RiverSession` for a single recording: the capture feeds it 16 kHz samples as they arrive,
/// `SpeechSegmenter` cuts them at pauses, each segment is decoded in order behind a serial
/// queue, and `SegmentJoiner` stitches the results. At release `finish()` decodes only what
/// was said since the last cut, so release-to-text is one short decode instead of the whole
/// dictation.
///
/// The engine only ever sees "transcribe this clip" (the injected `decode`); cut policy,
/// overlap and joins are River's, the same for every model.
///
/// Between cuts, the phrase still being spoken is decoded every so often while the queue is
/// idle, so the panel has text before the first pause. That provisional text is for the panel
/// only: a committed segment replaces it, and it is never part of the outcome.
///
/// Failure never leaves a hole: when a segment fails, streaming stops and everything from that
/// segment's start is decoded in one piece at release, which is today's one-shot path.
@MainActor
final class DictationStream {
    typealias Decode = @MainActor (_ samples: [Float]) async throws -> String

    struct Outcome {
        /// The whole transcript; empty when nothing was said.
        let text: String
        /// The failure of the decode at release, if any. Text before it is still in `text`.
        let error: Error?
    }

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "stream")
    private let decode: Decode
    private let sampleRate: Double = 16_000
    private let overlapSamples: Int
    private let tailMinVoicedSeconds: Double
    private let provisionalIntervalSamples: Int?
    private let provisionalMinVoicedSeconds: Double

    private(set) var samples: [Float] = []
    private var segmenter: SpeechSegmenter
    private var joiner = SegmentJoiner()
    private var queue: [(range: Range<Int>, cutAt: ContinuousClock.Instant)] = []
    private var worker: Task<Void, Never>?
    // The last segment whose words are in the transcript: the next one is decoded with its end in front.
    private var previous: Range<Int>?
    // Where streaming stopped after a failed segment; release decodes from here in one piece.
    private var failedFrom: Int?
    private var isCanceled = false
    private var isFinishing = false
    // The decode of the phrase still being spoken, shown after the transcript; never inserted.
    private var provisional = ""
    // Sample count when the last provisional decode started.
    private var provisionalFrom = 0
    private(set) var provisionalCount = 0

    /// Segments cut so far. Zero means the dictation never paused long enough to cut, and the
    /// session decodes it the ordinary way.
    private(set) var cutCount = 0

    /// Called whenever the shown text changes: the transcript, then any provisional text.
    var onTextChange: ((String) -> Void)?

    var text: String { joiner.text }
    var shownText: String { [joiner.text, provisional].filter { !$0.isEmpty }.joined(separator: " ") }

    init(
        decode: @escaping Decode,
        segmenter: SpeechSegmenter = SpeechSegmenter(),
        overlapSeconds: Double = Constants.streamingOverlapSeconds,
        tailMinVoicedSeconds: Double = Constants.streamingTailMinVoicedSeconds,
        provisionalIntervalSeconds: Double? = Constants.streamingProvisionalIntervalSeconds,
        provisionalMinVoicedSeconds: Double = Constants.streamingProvisionalMinVoicedSeconds
    ) {
        self.decode = decode
        self.segmenter = segmenter
        self.overlapSamples = Int(overlapSeconds * 16_000)
        self.tailMinVoicedSeconds = tailMinVoicedSeconds
        self.provisionalIntervalSamples = provisionalIntervalSeconds.map { Int($0 * 16_000) }
        self.provisionalMinVoicedSeconds = provisionalMinVoicedSeconds
    }

    /// Adds newly captured 16 kHz mono samples and queues any segment they complete.
    func append(_ newSamples: [Float]) {
        guard !isCanceled else { return }
        samples.append(contentsOf: newSamples)
        guard failedFrom == nil else { return }
        let start = segmenter.segmentStart
        var from = start
        for cut in segmenter.advance(over: samples) {
            cutCount += 1
            queue.append((from..<cut, .now))
            from = cut
        }
        pump()
    }

    /// Waits for queued segments, decodes what is left after the last cut, and returns the
    /// transcript. Call once, after the capture has delivered its last samples.
    func finish() async -> Outcome {
        isFinishing = true
        await settle()
        guard !isCanceled else { return Outcome(text: "", error: nil) }
        let tail = (failedFrom ?? segmenter.segmentStart)..<samples.count
        let start = ContinuousClock.now
        var tailError: Error?
        if failedFrom == nil, !joiner.isEmpty, segmenter.voicedSeconds(in: tail) < tailMinVoicedSeconds {
            // Room tone or a breath after the last phrase: decoding it is how "Thank you." gets in.
            logger.info("Tail skipped: \(self.seconds(tail.count), privacy: .public) s with no speech")
        } else if !tail.isEmpty {
            do {
                if failedFrom != nil {
                    try await decodeCold(tail)
                } else {
                    try await decodeSegment(tail)
                }
            } catch {
                tailError = error
                logger.error("Tail decode failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            }
            logger.info("Tail: \(self.seconds(tail.count), privacy: .public) s of audio decoded in \(self.elapsed(since: start), privacy: .public) s")
        }
        return Outcome(text: joiner.text, error: tailError)
    }

    /// Drops everything not yet decoded and ignores any decode still running.
    func cancel() {
        isCanceled = true
        queue.removeAll()
        worker?.cancel()
        worker = nil
    }

    /// `cancel()`, then waits for a decode still running, so the engine is free for the next.
    func cancelAndWait() async {
        let running = worker
        cancel()
        await running?.value
    }

    // internal for testability — waits for the segments queued so far to be decoded.
    func settle() async {
        while let worker { await worker.value }
    }

    // Starts the worker when idle: queued segments first, else a provisional decode if due.
    private func pump() {
        guard worker == nil, !isCanceled else { return }
        if !queue.isEmpty {
            worker = Task { @MainActor [weak self] in
                await self?.drain()
                self?.worker = nil
                self?.pump()
            }
        } else if let range = provisionalRangeIfDue() {
            provisionalFrom = samples.count
            worker = Task { @MainActor [weak self] in
                await self?.decodeProvisional(range)
                self?.worker = nil
                self?.pump()
            }
        }
    }

    private func provisionalRangeIfDue() -> Range<Int>? {
        guard let interval = provisionalIntervalSamples, !isFinishing, failedFrom == nil,
              samples.count - provisionalFrom >= interval else { return nil }
        let open = segmenter.segmentStart..<samples.count
        guard segmenter.voicedSeconds(in: open) >= provisionalMinVoicedSeconds else { return nil }
        return open
    }

    // Display only: a failure or an empty result changes nothing, and a cut since the decode
    // started makes the result stale (the committed segment will replace it).
    private func decodeProvisional(_ range: Range<Int>) async {
        guard let decoded = try? await decodeClip(range),
              !isCanceled, failedFrom == nil, segmenter.segmentStart == range.lowerBound else { return }
        provisionalCount += 1
        provisional = decoded.trimmingCharacters(in: .whitespaces)
        onTextChange?(shownText)
    }

    private func drain() async {
        while !isCanceled, failedFrom == nil, !queue.isEmpty {
            let (range, cutAt) = queue.removeFirst()
            let start = ContinuousClock.now
            do {
                try await decodeSegment(range)
                guard !isCanceled else { return }
                logger.info("Segment \(self.seconds(range.count), privacy: .public) s: decoded in \(self.elapsed(since: start), privacy: .public) s, cut-to-text \(self.elapsed(since: cutAt), privacy: .public) s, \(self.queue.count, privacy: .public) waiting")
            } catch {
                guard !isCanceled else { return }
                // Stop cutting; release decodes everything from here in one piece.
                failedFrom = range.lowerBound
                queue.removeAll()
                logger.error("Segment decode failed, streaming stopped: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            }
        }
    }

    // Decodes a segment with the previous one's end in front of it, falling back to a cold
    // decode when the overlap can't be aligned.
    private func decodeSegment(_ range: Range<Int>) async throws {
        if let previous, !joiner.isEmpty {
            let from = max(previous.lowerBound, range.lowerBound - overlapSamples)
            if let joint = try await decodeClip(from..<range.upperBound) {
                guard !isCanceled else { return }
                if joiner.appendOverlapped(joint) {
                    self.previous = range
                    provisional = ""
                    onTextChange?(shownText)
                    return
                }
                logger.info("Overlap did not align; decoding the segment on its own")
            }
        }
        try await decodeCold(range)
    }

    private func decodeCold(_ range: Range<Int>) async throws {
        guard let decoded = try await decodeClip(range) else {
            // Nothing said: the next segment has no overlap to align against.
            previous = nil
            if !provisional.isEmpty {
                provisional = ""
                onTextChange?(shownText)
            }
            return
        }
        guard !isCanceled else { return }
        joiner.appendCold(decoded)
        previous = range
        provisional = ""
        onTextChange?(shownText)
    }

    // The clip with silence trimmed, decoded; nil when it holds no speech.
    private func decodeClip(_ range: Range<Int>) async throws -> String? {
        let clip = AudioCaptureManager.trimSilence(Array(samples[range]))
        guard !clip.isEmpty else { return nil }
        do {
            return try await decode(clip)
        } catch TranscriptionError.noSpeechDetected {
            return nil
        }
    }

    private func seconds(_ count: Int) -> String { String(format: "%.2f", Double(count) / sampleRate) }

    private func elapsed(since start: ContinuousClock.Instant) -> String {
        let d = ContinuousClock.now - start
        return String(format: "%.2f", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
    }
}
