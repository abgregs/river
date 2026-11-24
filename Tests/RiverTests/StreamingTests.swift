import AVFoundation
import Foundation
import Testing
@testable import River

private let rate = 16_000
private func speech(_ seconds: Double, amplitude: Float = 0.1) -> [Float] {
    [Float](repeating: amplitude, count: Int(seconds * Double(rate)))
}
private func silence(_ seconds: Double) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * Double(rate)))
}

@Suite("SpeechSegmenter")
struct SpeechSegmenterTests {
    @Test("a pause after enough speech cuts the segment, keeping the word's decay")
    func pauseCut() {
        // 2 s of speech, then 1.2 s of quiet: the 1.0 s pause rule fires, and the cut lands
        // 0.2 s into the silence (the trim's tail pad) so the last word isn't clipped.
        var segmenter = SpeechSegmenter()
        let cuts = segmenter.advance(over: speech(2) + silence(1.2))
        #expect(cuts == [Int(2.2 * Double(rate))])
        #expect(segmenter.segmentStart == Int(2.2 * Double(rate)))
    }

    @Test("a pause after too little speech does not cut")
    func shortUtteranceRidesAlong() {
        // A one-second "yes" must not become its own segment: under 1.5 s of speech is the
        // pre-decode gate (fragments decode to partial words; noise to "Thank you.").
        var segmenter = SpeechSegmenter()
        #expect(segmenter.advance(over: speech(1) + silence(2)).isEmpty)
    }

    @Test("a thinking pause shorter than the threshold does not cut")
    func shortPauseNoCut() {
        var segmenter = SpeechSegmenter()
        #expect(segmenter.advance(over: speech(2) + silence(0.8) + speech(2)).isEmpty)
    }

    @Test("continuous speech is cut at its quietest point before the limit")
    func forcedCutAtQuietest() {
        // A speaker who never pauses: at 10 s the segment is cut at the quietest 100 ms in the
        // last 2 s. Cutting at an arbitrary instant garbled words (3–6 % WER); here the dip
        // at 9.0–9.1 s must be where the cut lands.
        var samples = speech(10.5)
        for i in Int(9.0 * Double(rate))..<Int(9.1 * Double(rate)) { samples[i] = 0.02 }
        var segmenter = SpeechSegmenter()
        let cuts = segmenter.advance(over: samples)
        #expect(cuts.count == 1)
        let cut = Double(cuts.first ?? 0) / Double(rate)
        #expect(cut > 9.0 && cut < 9.1)
    }

    @Test("feeding the audio in pieces cuts at the same places as all at once")
    func incrementalMatchesBatch() {
        // The capture delivers ~20 ms buffers; the result must not depend on buffer size,
        // or the eval harness replaying a file would not test what the app does.
        let samples = speech(2) + silence(1.2) + speech(3) + silence(1.5) + speech(0.5)
        var batch = SpeechSegmenter()
        let expected = batch.advance(over: samples)
        var live = SpeechSegmenter()
        var cuts: [Int] = []
        var fed = 0
        while fed < samples.count {
            fed = min(samples.count, fed + 357)
            cuts += live.advance(over: Array(samples[0..<fed]))
        }
        #expect(cuts == expected)
        #expect(expected.count == 2)
    }

    @Test("quiet room tone after speech counts as no speech")
    func tailVoicedSeconds() {
        var segmenter = SpeechSegmenter()
        let samples = speech(2) + silence(1.2) + speech(1, amplitude: 0.002)
        _ = segmenter.advance(over: samples)
        #expect(segmenter.voicedSeconds(in: segmenter.segmentStart..<samples.count) == 0)
    }
}

@Suite("SegmentJoiner")
struct SegmentJoinerTests {
    @Test("the overlap is stripped and the join takes the joint decode's punctuation")
    func overlapHealsSentenceBreak() {
        // Cold, segment one ends "option is." — the joint decode of the overlap shows the
        // sentence runs on, so the held period is dropped and nothing is repeated.
        var joiner = SegmentJoiner()
        joiner.appendCold("I think the best option is.")
        let aligned = joiner.appendOverlapped("the best option is to move the launch to next month.")
        #expect(aligned)
        #expect(joiner.text == "I think the best option is to move the launch to next month.")
    }

    @Test("a segment opening with a conjunction continues the sentence")
    func conjunctionRule() {
        var joiner = SegmentJoiner()
        joiner.appendCold("I think we should move the launch to next month.")
        let aligned = joiner.appendOverlapped("to next month. Because the team needs more time.")
        #expect(aligned)
        #expect(joiner.text == "I think we should move the launch to next month, because the team needs more time.")
    }

    @Test("a transcript ending in a function word is not a sentence end")
    func functionWordRule() {
        // Cold joins (no overlap) still get the rule: "about." can't end a sentence.
        var joiner = SegmentJoiner()
        joiner.appendCold("The budget for this quarter is about.")
        joiner.appendCold("Forty two thousand dollars.")
        #expect(joiner.text == "The budget for this quarter is about forty two thousand dollars.")
    }

    @Test("day names and I keep their capitals when a join lowercases")
    func keepCase() {
        var joiner = SegmentJoiner()
        joiner.appendCold("Only if they are free on.")
        joiner.appendCold("Tuesday or Wednesday.")
        #expect(joiner.text == "Only if they are free on Tuesday or Wednesday.")
    }

    @Test("a real sentence boundary is left alone")
    func sentenceBoundaryKept() {
        // "testing" is not a function word and "We" not a conjunction: the period stands.
        var joiner = SegmentJoiner()
        joiner.appendCold("The team needs more time for testing.")
        joiner.appendCold("We could also ask Maria.")
        #expect(joiner.text == "The team needs more time for testing. We could also ask Maria.")
    }

    @Test("an overlap that can't be found changes nothing")
    func missLeavesTextUnchanged() {
        // Typing from an unaligned joint decode would repeat words; the caller decodes cold.
        var joiner = SegmentJoiner()
        joiner.appendCold("Hello there.")
        let aligned = joiner.appendOverlapped("completely different words")
        #expect(!aligned)
        #expect(joiner.text == "Hello there.")
    }

    @Test("a joint decode with nothing new keeps the transcript")
    func nothingNew() {
        var joiner = SegmentJoiner()
        joiner.appendCold("Hello there.")
        let aligned = joiner.appendOverlapped("hello there.")
        #expect(aligned)
        #expect(joiner.text == "Hello there.")
    }
}

/// Canned decoder: returns the next answer per call and records what it was given; nil is a
/// model that heard no speech, as once the answers run out.
@MainActor
private final class FakeDecoder {
    var answers: [Result<String?, Error>]
    private(set) var clipSeconds: [Double] = []
    init(_ answers: [Result<String?, Error>]) { self.answers = answers }
    func decode(_ samples: [Float]) async throws -> String? {
        clipSeconds.append(Double(samples.count) / Double(rate))
        guard !answers.isEmpty else { return nil }
        return try answers.removeFirst().get()
    }
}

private struct DecodeFailed: Error {}

/// Holds its first decode until `release()`, so a test can stop the dictation while that
/// decode is still running. Every decode suspends, as a real one does: an answer that never
/// suspends lets queued work finish before anything else runs and hides ordering bugs.
@MainActor
private final class HeldDecoder {
    var answers: [String]
    private(set) var calls = 0
    private var held: CheckedContinuation<Void, Never>?
    var isHolding: Bool { held != nil }
    init(_ answers: [String]) { self.answers = answers }
    func decode(_ samples: [Float]) async throws -> String? {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation { held = $0 }
        } else {
            await Task.yield()
        }
        return answers.removeFirst()
    }
    func release() {
        held?.resume()
        held = nil
    }
}


@Suite("DictationStream")
struct DictationStreamTests {
    @MainActor
    @Test("segments are decoded while speaking and only the tail at release")
    func streamsThenTail() async {
        let decoder = FakeDecoder([.success("Hello there."), .success("hello there. General Kenobi.")])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        var shown: [String] = []
        stream.onTextChange = { shown.append($0) }

        stream.append(speech(2) + silence(1.2))
        await stream.settle()
        // The first phrase is on screen before the user lets go.
        #expect(shown == ["Hello there."])
        #expect(decoder.clipSeconds.count == 1)

        stream.append(speech(2))
        let outcome = await stream.finish()
        #expect(outcome.text == "Hello there. General Kenobi.")
        #expect(outcome.error == nil)
        // The tail carried the previous segment's end in front of it for the join.
        #expect(decoder.clipSeconds.count == 2)
        #expect(decoder.clipSeconds[1] > 2.5)
    }

    @MainActor
    @Test("a failed segment hands everything from it to one decode at release")
    func failureFallsBackToOneShot() async {
        // No hole and no immediate retry: streaming stops, later pauses are not decoded, and
        // release decodes from the failed segment's start, as the one-shot path would.
        let decoder = FakeDecoder([.failure(DecodeFailed()), .success("The whole thing.")])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        stream.append(speech(2) + silence(1.2))
        await stream.settle()
        stream.append(speech(2) + silence(1.2) + speech(1))
        await stream.settle()
        #expect(decoder.clipSeconds.count == 1)

        let outcome = await stream.finish()
        #expect(outcome.text == "The whole thing.")
        #expect(decoder.clipSeconds.count == 2)
        #expect(decoder.clipSeconds[1] > 6)
    }

    @MainActor
    @Test("a tail of room tone after speech is not decoded")
    func silentTailSkipped() async {
        // Decoding noise is how "Thank you." gets typed (distil, review §4).
        let decoder = FakeDecoder([.success("Hello there."), .success("Thank you.")])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        stream.append(speech(2) + silence(1.2) + speech(1, amplitude: 0.002))
        let outcome = await stream.finish()
        #expect(outcome.text == "Hello there.")
        #expect(decoder.clipSeconds.count == 1)
    }

    @MainActor
    @Test("a segment the model hears nothing in keeps streaming: both segments decode as the user speaks")
    func nothingHeardKeepsStreaming() async {
        // A failure in place of nil would stop streaming after the first segment (planning 0039).
        let decoder = FakeDecoder([.success(nil), .success("Second phrase.")])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        stream.append(speech(2) + silence(1.2) + speech(2) + silence(1.2))
        await stream.settle()
        #expect(decoder.clipSeconds.count == 2)
        let outcome = await stream.finish()
        #expect(outcome.text == "Second phrase.")
        #expect(outcome.error == nil)
    }

    @MainActor
    @Test("a segment that holds no speech is dropped, and the next decodes cold")
    func noSpeechSegment() async {
        let decoder = FakeDecoder([.success(nil), .success("Second phrase.")])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        stream.append(speech(2) + silence(1.2) + speech(2))
        let outcome = await stream.finish()
        #expect(outcome.text == "Second phrase.")
        #expect(outcome.error == nil)
        // No overlap after a dropped segment: the tail clip is only its own audio.
        #expect(decoder.clipSeconds[1] < 3)
    }

    @MainActor
    @Test("a failed tail returns the text before it along with the error")
    func tailFailureKeepsText() async {
        let decoder = FakeDecoder([.success("Hello there."), .failure(DecodeFailed()), .failure(DecodeFailed())])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        stream.append(speech(2) + silence(1.2) + speech(2))
        let outcome = await stream.finish()
        #expect(outcome.text == "Hello there.")
        #expect(outcome.error != nil)
    }

    @MainActor
    @Test("the phrase being spoken shows before any pause")
    func provisionalBeforePause() async {
        // Without it the panel stays empty until the first one-second pause, so a short or
        // unbroken dictation shows nothing at all (the first on-device test).
        let decoder = FakeDecoder([.success("Hello the")])
        let stream = DictationStream(decode: decoder.decode)
        var shown: [String] = []
        stream.onTextChange = { shown.append($0) }
        stream.append(speech(2))
        await stream.settle()
        #expect(shown == ["Hello the"])
        #expect(stream.cutCount == 0)
        #expect(stream.text.isEmpty)
    }

    @MainActor
    @Test("a committed segment replaces the provisional text, which is never inserted")
    func provisionalReplacedByCommit() async {
        // Provisional decodes see a phrase cut off mid-word; only the committed decode of the
        // whole segment may reach the outcome that gets typed.
        let decoder = FakeDecoder([.success("Hello the"), .success("Hello there.")])
        let stream = DictationStream(decode: decoder.decode)
        var shown: [String] = []
        stream.onTextChange = { shown.append($0) }
        stream.append(speech(2))
        await stream.settle()
        stream.append(silence(1.2))
        let outcome = await stream.finish()
        #expect(shown == ["Hello the", "Hello there."])
        #expect(outcome.text == "Hello there.")
    }

    @MainActor
    @Test("with the live text hidden, no provisional decode runs and committed segments still decode")
    func hiddenRunsNoPreview() async {
        // Hidden is the default, so most dictations must not pay for text nobody sees, while
        // release stays one short decode (planning 0034, decision 3).
        let decoder = FakeDecoder([.success("Hello there.")])
        let stream = DictationStream(decode: decoder.decode)
        stream.showsPreview = false
        var shown: [String] = []
        stream.onTextChange = { shown.append($0) }
        stream.append(speech(2))
        await stream.settle()
        #expect(decoder.clipSeconds.isEmpty)
        stream.append(silence(1.2))
        await stream.settle()
        #expect(shown == ["Hello there."])
        #expect(stream.provisionalCount == 0)
    }

    @MainActor
    @Test("hiding keeps the last provisional text, and showing again starts no decode by itself")
    func hideKeepsLastPreview() async {
        // Toggling back and forth must cost no more than leaving the text shown.
        let decoder = FakeDecoder([.success("Hello the")])
        let stream = DictationStream(decode: decoder.decode)
        stream.append(speech(2))
        await stream.settle()
        #expect(stream.shownText == "Hello the")
        stream.showsPreview = false
        stream.append(speech(1))
        await stream.settle()
        #expect(decoder.clipSeconds.count == 1)
        #expect(stream.shownText == "Hello the")
        stream.showsPreview = true
        await stream.settle()
        #expect(decoder.clipSeconds.count == 1)
    }

    @MainActor
    @Test("a provisional decode still running when the text is hidden is dropped")
    func hideDropsRunningPreview() async {
        let decoder = HeldDecoder(["Hello the"])
        let stream = DictationStream(decode: decoder.decode)
        var shown: [String] = []
        stream.onTextChange = { shown.append($0) }
        stream.append(speech(2))
        while !decoder.isHolding { await Task.yield() }
        stream.showsPreview = false
        decoder.release()
        await stream.settle()
        #expect(shown.isEmpty)
        #expect(stream.provisionalCount == 0)
    }

    @MainActor
    @Test("too little speech gets no provisional decode")
    func provisionalNeedsSpeech() async {
        // A half-second fragment decodes as a partial or invented word.
        let decoder = FakeDecoder([.success("Thank you.")])
        let stream = DictationStream(decode: decoder.decode)
        stream.append(speech(0.6) + silence(0.5))
        await stream.settle()
        #expect(decoder.clipSeconds.isEmpty)
    }

    @MainActor
    @Test("an abrupt stop finishes every pending join before the text is typed")
    func abruptStopCompletesJoins() async {
        // Fast speech, then release: a provisional decode is still running and two segments
        // are waiting behind it. The typed text must have every segment joined (overlap and
        // join rules) and none of the provisional text (the maintainer's on-device check).
        let decoder = HeldDecoder([
            "Hello the",                                                // provisional, stale by the time it returns
            "I think the best option is.",                              // segment 1, cold
            "the best option is to move the launch to next month.",     // segment 2, with segment 1's end in front
            "next month. Because the team needs more time.",            // the tail, with segment 2's end in front
        ])
        let stream = DictationStream(decode: decoder.decode)
        var shown: [String] = []
        stream.onTextChange = { shown.append($0) }

        stream.append(speech(2))
        for _ in 0..<100 where !decoder.isHolding { await Task.yield() }
        #expect(decoder.isHolding)
        stream.append(silence(1.2) + speech(2) + silence(1.2) + speech(1.5))
        #expect(stream.cutCount == 2)

        // Runs once `finish()` is waiting on the held decode.
        Task { decoder.release() }
        let outcome = await stream.finish()

        #expect(outcome.text == "I think the best option is to move the launch to next month, because the team needs more time.")
        #expect(outcome.error == nil)
        #expect(decoder.calls == 4)
        #expect(!shown.contains("Hello the"))
    }

    @MainActor
    @Test("cancel discards the transcript")
    func cancelDiscards() async {
        let decoder = FakeDecoder([.success("Hello there."), .success("More.")])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        stream.append(speech(2) + silence(1.2))
        stream.cancel()
        let outcome = await stream.finish()
        #expect(outcome.text.isEmpty)
    }

    // MARK: Every path in one piece (planning 0039)

    @MainActor
    @Test("with no pause long enough to cut, release decodes the whole recording once, trimmed")
    func noCutDecodesInOnePiece() async {
        // Nothing was decoded while the user spoke, so release decodes all of it in one call, with
        // the silence around the speech trimmed: 0.5 s kept before it and 0.2 s after.
        let decoder = FakeDecoder([.success("Hello there.")])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        stream.append(silence(1) + speech(2) + silence(0.5))
        await stream.settle()
        #expect(decoder.clipSeconds.isEmpty)

        let outcome = await stream.finish()
        #expect(outcome.text == "Hello there.")
        #expect(outcome.error == nil)
        #expect(decoder.clipSeconds == [2.7])
    }

    @MainActor
    @Test("with streaming off, nothing is decoded while speaking, and release decodes the recording once")
    func streamingOffDecodesAtRelease() async {
        // The hidden streamingDictation switch: a pause that would cut stays inside the one clip.
        let decoder = FakeDecoder([.success("Hello there. General Kenobi.")])
        let stream = DictationStream(decode: decoder.decode, streaming: false)
        stream.append(speech(2) + silence(1.2) + speech(2))
        await stream.settle()
        #expect(stream.cutCount == 0)
        #expect(decoder.clipSeconds.isEmpty)

        let outcome = await stream.finish()
        #expect(outcome.text == "Hello there. General Kenobi.")
        #expect(decoder.clipSeconds == [5.2])
    }

    @MainActor
    @Test("a recording the trim leaves empty is not decoded and never waits for the model")
    func silenceNeverWaits() async {
        // A stray tap while the model downloads would otherwise hold River in processing until the
        // model is ready, and then decode room tone (planning 0004, 0023).
        let decoder = FakeDecoder([.success("Thank you.")])
        let stream = DictationStream(decode: decoder.decode)
        stream.append(silence(2))
        var waits = 0
        let outcome = await stream.finish { _ in
            waits += 1
            return true
        }
        #expect(outcome.text.isEmpty)
        #expect(outcome.error == nil)
        #expect(waits == 0)
        #expect(decoder.clipSeconds.isEmpty)
    }

    @MainActor
    @Test("release waits before a one-piece decode, with the clip it then decodes")
    func waitsWithTheClipItDecodes() async {
        // A failed load keeps the clip the wait was given, so it must be the audio the decode would
        // have had (planning 0004).
        let decoder = FakeDecoder([.success("Hello there.")])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        stream.append(silence(1) + speech(2) + silence(0.5))
        var waited: [Double] = []
        let outcome = await stream.finish { clip in
            #expect(decoder.clipSeconds.isEmpty)
            waited.append(Double(clip.count) / Double(rate))
            return true
        }
        #expect(waited == [2.7])
        #expect(decoder.clipSeconds == waited)
        #expect(outcome.text == "Hello there.")
    }

    @MainActor
    @Test("a wait that ends the dictation decodes nothing and returns no text")
    func endedWaitDecodesNothing() async {
        // The load failed and the recording is kept, or Cancel Dictation threw it away: either way
        // nothing is typed now (planning 0004).
        let decoder = FakeDecoder([.success("Hello there.")])
        let stream = DictationStream(decode: decoder.decode, provisionalIntervalSeconds: nil)
        stream.append(speech(2))
        let outcome = await stream.finish { _ in false }
        #expect(outcome.text.isEmpty)
        #expect(outcome.error == nil)
        #expect(decoder.clipSeconds.isEmpty)
    }

    @MainActor
    @Test("a streamed tail is decoded without a wait; the one piece after a failed segment waits")
    func onlyOnePieceWaits() async {
        // A segment decoded, so the model is ready for the tail. A failed segment can mean it
        // isn't ready yet, so everything from there waits for it.
        let streamed = FakeDecoder([.success("Hello there."), .success("hello there. General Kenobi.")])
        let first = DictationStream(decode: streamed.decode, provisionalIntervalSeconds: nil)
        first.append(speech(2) + silence(1.2) + speech(2))
        var waits = 0
        let tailOutcome = await first.finish { _ in
            waits += 1
            return true
        }
        #expect(tailOutcome.text == "Hello there. General Kenobi.")
        #expect(waits == 0)

        let failing = FakeDecoder([.failure(DecodeFailed()), .success("The whole thing.")])
        let second = DictationStream(decode: failing.decode, provisionalIntervalSeconds: nil)
        second.append(speech(2) + silence(1.2) + speech(2))
        let outcome = await second.finish { _ in
            waits += 1
            return true
        }
        #expect(outcome.text == "The whole thing.")
        #expect(waits == 1)
    }

    @MainActor
    @Test("with no cut, the one-piece text replaces the provisional text")
    func onePieceReplacesProvisional() async {
        // The panel ends on what is typed, never on a phrase cut off mid-word.
        let decoder = FakeDecoder([.success("Hello the"), .success("Hello there.")])
        let stream = DictationStream(decode: decoder.decode)
        var shown: [String] = []
        stream.onTextChange = { shown.append($0) }
        stream.append(speech(2))
        await stream.settle()
        let outcome = await stream.finish()
        #expect(shown == ["Hello the", "Hello there."])
        #expect(outcome.text == "Hello there.")
    }

    @MainActor
    @Test("a kept recording is decoded in one piece, trimmed, and one with no speech not at all")
    func keptRecordingInOnePiece() async {
        // A recording a failed load kept is decoded later as its dictation would have been.
        let decoder = FakeDecoder([.success("Hello there.")])
        let outcome = await DictationStream.transcribe(silence(1) + speech(2) + silence(1.5), decode: decoder.decode)
        #expect(outcome.text == "Hello there.")
        #expect(decoder.clipSeconds == [2.7])

        let silent = await DictationStream.transcribe(silence(1), decode: decoder.decode)
        #expect(silent.text.isEmpty)
        #expect(decoder.clipSeconds == [2.7])
    }
}

@Suite("DictationStream silence trim")
struct DictationStreamSilenceTrimTests {
    // Whisper hallucinates text from silence — pasting words the user never spoke
    // is this app's worst failure. `trimSilence` drops below-threshold audio at
    // both ends of each 16 kHz clip, keeping a margin so speech is never clipped.
    // See planning 0023.

    @Test("all-silence input trims to empty")
    func allSilenceTrimsToEmpty() {
        // An accidental activation captures pure silence. It must trim to empty so
        // nothing is decoded — no hallucinated paste.
        let silence = [Float](repeating: 0, count: 16_000)  // 1 s of digital silence
        #expect(DictationStream.trimSilence(silence).isEmpty)
    }

    @Test("empty input trims to empty")
    func emptyTrimsToEmpty() {
        #expect(DictationStream.trimSilence([]).isEmpty)
    }

    @Test("silence-padded speech keeps the speech with a margin, dropping the padding")
    func paddedSpeechPreservesSpeech() {
        // 1 s silence, 0.5 s voiced, 1 s silence at 16 kHz. The silence beyond the
        // lead-in and tail margins must be dropped, but the speech and its margins
        // must survive intact.
        let pad = [Float](repeating: 0, count: 16_000)
        let speech = sineSamples(count: 8_000, frequency: 440, amplitude: 0.5)
        let padded = pad + speech + pad

        let out = DictationStream.trimSilence(padded)

        #expect(out.count < padded.count)           // padding trimmed
        #expect(out.count >= speech.count)          // speech + margins survive
        #expect(out.count < padded.count - 16_000)  // most of the silence is gone
        let rms = (out.reduce(Float(0)) { $0 + $1 * $1 } / Float(out.count)).squareRoot()
        #expect(rms > 0.1)                         // preserved speech carries energy
    }

    @Test("speech-only input is returned untouched")
    func speechOnlyUntouched() {
        // No silence to trim: every window is voiced, so the whole buffer survives
        // (the margin clamps to the array bounds). Length is unchanged.
        let speech = sineSamples(count: 16_000, frequency: 440, amplitude: 0.5)
        #expect(DictationStream.trimSilence(speech).count == speech.count)
    }

    // The maintainer's smoke: quiet talking on a built-in mic never reached transcription
    // under the fixed -40 dBFS gate, so nothing was typed.
    @Test("a quiet dictation survives the trim instead of being discarded whole")
    func quietDictationSurvives() {
        let pad = [Float](repeating: 0, count: 8_000)
        let quiet = sineSamples(count: 8_000, frequency: 440, amplitude: sineAmplitude(decibels: -44))
        let padded = pad + quiet + pad
        let fixedGate = DictationStream.trimSilence(padded, peakRatio: 1, floor: Constants.silenceTrimEnergyThreshold)
        #expect(fixedGate.isEmpty)
        #expect(DictationStream.trimSilence(padded).count >= quiet.count)
    }

    // Planning 0023: room tone left after speech can decode as invented text, so a normal
    // dictation's tail must be cut exactly where the fixed gate cut it.
    @Test("normal speech keeps the fixed gate, so its quiet tail is still cut")
    func normalSpeechTrimsAsBefore() {
        let speech = sineSamples(count: 8_000, frequency: 440, amplitude: 0.5)
        let tail = sineSamples(count: 16_000, frequency: 440, amplitude: sineAmplitude(decibels: -45))
        let recording = speech + tail
        let trimmed = DictationStream.trimSilence(recording)
        #expect(trimmed == DictationStream.trimSilence(recording, peakRatio: 1, floor: Constants.silenceTrimEnergyThreshold))
        #expect(trimmed.count < speech.count + tail.count / 2)
    }

    // The maintainer's smoke (2026-09-26): with 0.1 s kept before a word, quick taps of
    // "hello there" reached Whisper clipped mid-word and decoded to nothing; the lead-in
    // is the context it needs. The tail stays short, since room tone after speech is what
    // Whisper turns into invented text (planning 0023).
    @Test("the trim keeps half a second before speech and a fifth of a second after")
    func trimKeepsLeadInAndShortTail() {
        let silence = [Float](repeating: 0, count: 16_000)
        let speech = sineSamples(count: 8_000, frequency: 440, amplitude: 0.5)
        let out = DictationStream.trimSilence(silence + speech + silence)
        #expect(Constants.silenceTrimLeadSeconds == 0.5)
        #expect(Constants.silenceTrimTailSeconds == 0.2)
        #expect(out.count == Int(Constants.silenceTrimLeadSeconds * 16_000) + speech.count + Int(Constants.silenceTrimTailSeconds * 16_000))
    }

    // An accidental activation in a quiet room must still decode nothing.
    @Test("near-silence below the floor still trims to empty")
    func nearSilenceTrimsToEmpty() {
        let roomTone = sineSamples(count: 16_000, frequency: 440, amplitude: sineAmplitude(decibels: -56))
        #expect(DictationStream.trimSilence(roomTone).isEmpty)
    }
}

// Peak amplitude of a sine whose RMS is this many decibels of full scale.
private func sineAmplitude(decibels: Double) -> Float {
    Float(pow(10, decibels / 20) * 2.0.squareRoot())
}

// A 16 kHz mono sample array holding a pure sine: a synthetic "speech" signal with known
// energy for the trim tests.
private func sineSamples(
    count: Int, frequency: Double, amplitude: Float, sampleRate: Double = 16_000
) -> [Float] {
    (0..<count).map { amplitude * Float(sin(2.0 * .pi * frequency * Double($0) / sampleRate)) }
}
