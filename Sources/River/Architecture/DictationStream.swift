import Foundation
import os

/// One dictation's audio, from the press to the text, and the one place that decides what audio
/// each decode gets (planning 0039). Owned by `RiverSession` for a single recording: the capture
/// feeds it the recording as 16 kHz samples as they arrive, and `finish()` turns it into text at
/// release. The engine only ever sees "transcribe this clip" (the injected `decode`); the silence
/// trim, the cuts, the overlap, the joins and the one-piece fallbacks are River's, the same for
/// every model. What one engine needs of a clip, such as padding a short one, sits behind it.
///
/// While the user speaks (0025 streaming), `SpeechSegmenter` cuts the samples at pauses, each
/// segment is decoded in order behind a serial queue, and `SegmentJoiner` stitches the results.
/// At release `finish()` decodes only what was said since the last cut, so release-to-text is one
/// short decode instead of the whole dictation. Between cuts, the phrase still being spoken is
/// decoded every so often while the queue is idle, so the panel has text before the first pause.
/// That provisional text is for the panel only: a committed segment replaces it, and it is never
/// part of the outcome.
///
/// Every other dictation is decoded in one piece at release: one with no pause long enough to
/// cut, one recorded with streaming off (the hidden `streamingDictation` switch), and one whose
/// segment failed, from that segment's start, so a failure never leaves a hole. A segment the
/// model hears no speech in is not a failure: it adds nothing, and streaming goes on. A recording
/// a failed load kept is decoded the same way later (`transcribe(_:decode:)`).
@MainActor
final class DictationStream {
    /// The text, or nil when the model heard no speech (`TranscriptionManager.transcribe`).
    typealias Decode = @MainActor (_ samples: [Float]) async throws -> String?

    struct Outcome {
        /// The whole transcript; empty when nothing was said.
        let text: String
        /// The failure of the decode at release, if any. Text before it is still in `text`.
        let error: Error?
        /// Why `text` is empty, when it is and nothing failed, so a model that stops hearing
        /// speech shows in the log rather than passing as silence (planning 0039).
        let emptyReason: EmptyReason?
    }

    /// Why a dictation has nothing to type.
    enum EmptyReason {
        /// No clip reached the engine: the trim left nothing.
        case trimmedToNothing
        /// The engine got audio and heard no speech.
        case noSpeechHeard
        /// The engine wrote only punctuation, which the joiner drops.
        case noWords
        /// It ended before its decode: a failed load kept it, Cancel Dictation threw it away, or
        /// the stream was canceled.
        case ended
    }

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "stream")
    private let decode: Decode
    private let sampleRate: Double = 16_000
    private let streams: Bool
    private let overlapSamples: Int
    private let tailMinVoicedSeconds: Double
    private let provisionalIntervalSamples: Int?
    private let provisionalMinVoicedSeconds: Double

    private var samples: [Float] = []
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
    // Whether a decode for the transcript reached the engine, and whether one heard words:
    // why an empty transcript is empty. Previews don't count.
    private var hasReachedEngine = false
    private var hasHeardWords = false
    // The decode of the phrase still being spoken, shown after the transcript; never inserted.
    private var provisional = ""
    // Sample count when the last provisional decode started.
    private var provisionalFrom = 0
    private(set) var provisionalCount = 0

    /// Segments cut so far. Zero means the dictation never paused long enough to cut, or
    /// streaming was off, and release decodes it in one piece.
    private(set) var cutCount = 0

    /// Called whenever the shown text changes: the transcript, then any provisional text.
    var onTextChange: ((String) -> Void)?

    /// Whether the phrase still being spoken is decoded for the panel (planning 0034, decision
    /// 3). Off while the live text is hidden: no new provisional decode starts, one already
    /// running is dropped, and the last provisional text stays. Turning it on starts nothing
    /// by itself; the next one runs when due.
    var showsPreview = true

    var text: String { joiner.text }
    var shownText: String { [joiner.text, provisional].filter { !$0.isEmpty }.joined(separator: " ") }

    /// `streaming` false keeps every decode for release: nothing is cut or decoded while the
    /// user speaks, and the recording is decoded in one piece.
    init(
        decode: @escaping Decode,
        streaming: Bool = true,
        segmenter: SpeechSegmenter = SpeechSegmenter(),
        overlapSeconds: Double = Constants.streamingOverlapSeconds,
        tailMinVoicedSeconds: Double = Constants.streamingTailMinVoicedSeconds,
        provisionalIntervalSeconds: Double? = Constants.streamingProvisionalIntervalSeconds,
        provisionalMinVoicedSeconds: Double = Constants.streamingProvisionalMinVoicedSeconds
    ) {
        self.decode = decode
        self.streams = streaming
        self.segmenter = segmenter
        self.overlapSamples = Int(overlapSeconds * 16_000)
        self.tailMinVoicedSeconds = tailMinVoicedSeconds
        self.provisionalIntervalSamples = provisionalIntervalSeconds.map { Int($0 * 16_000) }
        self.provisionalMinVoicedSeconds = provisionalMinVoicedSeconds
    }

    /// A recording a failed load kept (planning 0004), decoded in one piece through the same
    /// path as a dictation's release. There is no wait: it runs once the model is ready.
    static func transcribe(_ recording: [Float], decode: @escaping Decode) async -> Outcome {
        let stream = DictationStream(decode: decode, streaming: false)
        stream.append(recording)
        return await stream.finish()
    }

    /// Adds newly captured 16 kHz mono samples and queues any segment they complete.
    func append(_ newSamples: [Float]) {
        guard !isCanceled else { return }
        samples.append(contentsOf: newSamples)
        guard streams, failedFrom == nil else { return }
        let start = segmenter.segmentStart
        var from = start
        for cut in segmenter.advance(over: samples) {
            cutCount += 1
            queue.append((from..<cut, .now))
            from = cut
        }
        pump()
    }

    /// Waits for queued segments, decodes what is left, and returns the transcript: the tail
    /// after the last cut, or else everything not yet decoded, in one piece. Call once, after the
    /// capture has delivered its last samples. The shown text ends as the transcript, with no
    /// provisional text after it.
    ///
    /// `whenReady` is the session's wait for the model (planning 0004). It runs before a
    /// one-piece decode, and only when its clip holds speech after the trim, so a stray tap never
    /// waits; it gets that clip, which a failed load keeps, and returns false when the dictation
    /// ends there, which cancels the stream. The tail needs no wait: a segment decoded before it.
    func finish(whenReady: @MainActor (_ clip: [Float]) async -> Bool = { _ in true }) async -> Outcome {
        isFinishing = true
        await settle()
        guard !isCanceled else { return Outcome(text: "", error: nil, emptyReason: .ended) }
        let rest = (failedFrom ?? segmenter.segmentStart)..<samples.count
        var failure: Error?
        do {
            if failedFrom == nil, cutCount > 0 {
                try await decodeTail(rest)
            } else {
                guard try await decodeInOnePiece(rest, whenReady: whenReady) else {
                    cancel()
                    return Outcome(text: "", error: nil, emptyReason: .ended)
                }
            }
        } catch {
            failure = error
            logger.error("Release decode failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
        }
        if !provisional.isEmpty {
            provisional = ""
            onTextChange?(shownText)
        }
        let text = joiner.text
        return Outcome(text: text, error: failure, emptyReason: text.isEmpty && failure == nil ? emptyReason : nil)
    }

    // Why nothing joined the transcript, from what its decodes did.
    private var emptyReason: EmptyReason {
        if hasHeardWords { return .noWords }
        return hasReachedEngine ? .noSpeechHeard : .trimmedToNothing
    }

    /// Drops everything not yet decoded and ignores any decode still running.
    func cancel() {
        isCanceled = true
        queue.removeAll()
        worker?.cancel()
        worker = nil
    }

    // internal for testability — waits for the segments queued so far to be decoded.
    func settle() async {
        while let worker { await worker.value }
    }

    // internal for testability — leading/trailing silence trim on a 16 kHz mono clip, run on
    // every clip right before it is decoded. Whisper's worst failure mode is inventing text
    // ("Thank you for watching.") from silent audio: an accidental activation captures pure
    // silence, and every real utterance carries trailing breath. Drop quiet RMS windows at
    // both ends, keeping `leadSeconds` before detected speech and `tailSeconds` after it, so a
    // word's soft onset survives. The gate is `energyThreshold` for normal speech and drops
    // toward `floor` for a quiet recording, tracking its loudest window, so a whispered
    // dictation is kept rather than discarded whole. All-silence in → [] out: nothing was
    // said, so nothing is decoded (planning 0023). Pure.
    nonisolated static func trimSilence(
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
        guard showsPreview, let interval = provisionalIntervalSamples, !isFinishing, failedFrom == nil,
              samples.count - provisionalFrom >= interval else { return nil }
        let open = segmenter.segmentStart..<samples.count
        guard segmenter.voicedSeconds(in: open) >= provisionalMinVoicedSeconds else { return nil }
        return open
    }

    // Display only: a failure or an empty result changes nothing, a cut since the decode
    // started makes the result stale (the committed segment will replace it), and a hide
    // since it started drops it.
    private func decodeProvisional(_ range: Range<Int>) async {
        guard let decoded = try? await decodeClip(range, forTranscript: false), showsPreview,
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

    // What was said since the last cut. Room tone or a breath after the last phrase is left
    // out: decoding it is how "Thank you." gets in.
    private func decodeTail(_ tail: Range<Int>) async throws {
        if !joiner.isEmpty, segmenter.voicedSeconds(in: tail) < tailMinVoicedSeconds {
            logger.info("Tail skipped: \(self.seconds(tail.count), privacy: .public) s with no speech")
            return
        }
        guard !tail.isEmpty else { return }
        let start = ContinuousClock.now
        try await decodeSegment(tail)
        logger.info("Tail: \(self.seconds(tail.count), privacy: .public) s of audio decoded in \(self.elapsed(since: start), privacy: .public) s")
    }

    // The one-piece decode: `range` trimmed once, waited for, and decoded in one call. False
    // when `whenReady` ended the dictation.
    private func decodeInOnePiece(_ range: Range<Int>, whenReady: @MainActor (_ clip: [Float]) async -> Bool) async throws -> Bool {
        let clip = Self.trimSilence(Array(samples[range]))
        guard !clip.isEmpty else {
            logger.info("One piece: no speech in \(self.seconds(range.count), privacy: .public) s, nothing to decode")
            return true
        }
        guard await whenReady(clip) else { return false }
        let start = ContinuousClock.now
        join(try await decodeForTranscript(clip), decodedAlone: range)
        logger.info("One piece: \(self.seconds(clip.count), privacy: .public) s of audio decoded in \(self.elapsed(since: start), privacy: .public) s")
        return true
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
        join(try await decodeClip(range), decodedAlone: range)
    }

    // A clip decoded on its own joins the transcript as it is. Nothing said adds nothing, and
    // the next segment has no overlap to align against.
    private func join(_ decoded: String?, decodedAlone range: Range<Int>) {
        guard let decoded else {
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
    private func decodeClip(_ range: Range<Int>, forTranscript: Bool = true) async throws -> String? {
        let clip = Self.trimSilence(Array(samples[range]))
        guard !clip.isEmpty else { return nil }
        if forTranscript { return try await decodeForTranscript(clip) }
        return try await decode(clip)
    }

    // A decode whose text can join the transcript, noted for an empty outcome's reason.
    private func decodeForTranscript(_ clip: [Float]) async throws -> String? {
        hasReachedEngine = true
        let decoded = try await decode(clip)
        if decoded != nil { hasHeardWords = true }
        return decoded
    }

    private func seconds(_ count: Int) -> String { String(format: "%.2f", Double(count) / sampleRate) }

    private func elapsed(since start: ContinuousClock.Instant) -> String {
        let d = ContinuousClock.now - start
        return String(format: "%.2f", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
    }
}
