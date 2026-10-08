import Foundation

/// Decides where a live dictation is cut into segments that can be decoded while the user
/// keeps talking (0025 review §2). Pure and incremental: feed it the whole 16 kHz buffer as it
/// grows and it returns the sample indices of any new cuts, so the eval harness can replay a
/// recording through the exact rule the app uses.
///
/// Two rules:
/// - **Pause cut**: `pauseSeconds` of silence after at least `minVoicedSeconds` of speech in
///   the segment. The cut lands `tailPadSeconds` into the silence, so the last word's decay
///   stays with its segment.
/// - **Forced cut**: a segment that reaches `maxSegmentSeconds` (someone who never pauses) is
///   cut at the quietest 100 ms in its last `forcedSearchSeconds`. A cut at an arbitrary
///   instant garbles the word it lands in (3–6 % WER measured); the quietest point cost none.
///
/// A segment is never cut with less than `minVoicedSeconds` of speech in it, which is also
/// the pre-decode voiced gate: distil-large-v3 decodes noise as "Thank you.", and short
/// fragments decode as plausible partial words (review §4).
///
/// "Voiced" is the silence trim's gate (planning 0023): a fixed energy threshold that drops
/// toward a floor for a quiet speaker, tracking the loudest window so far.
struct SpeechSegmenter {
    let sampleRate: Double
    let pauseSeconds: Double
    let minVoicedSeconds: Double
    let maxSegmentSeconds: Double
    let forcedSearchSeconds: Double
    let tailPadSeconds: Double
    let energyThreshold: Float
    let peakRatio: Float
    let floor: Float

    /// 20 ms analysis windows, as in the silence trim.
    let windowSamples: Int

    /// First sample of the segment being collected; everything before it has been cut.
    private(set) var segmentStart = 0
    /// RMS of every complete window seen so far, from the start of the dictation.
    private(set) var windowRMS: [Float] = []
    private var peak: Float = 0
    private var voicedWindows = 0
    private var silentRun = 0

    init(
        sampleRate: Double = 16_000,
        pauseSeconds: Double = Constants.streamingPauseSeconds,
        minVoicedSeconds: Double = Constants.streamingMinVoicedSeconds,
        maxSegmentSeconds: Double = Constants.streamingMaxSegmentSeconds,
        forcedSearchSeconds: Double = Constants.streamingForcedCutSearchSeconds,
        tailPadSeconds: Double = Constants.silenceTrimTailSeconds,
        energyThreshold: Float = Constants.silenceTrimEnergyThreshold,
        peakRatio: Float = Constants.silenceTrimPeakRatio,
        floor: Float = Constants.silenceTrimFloor
    ) {
        self.sampleRate = sampleRate
        self.pauseSeconds = pauseSeconds
        self.minVoicedSeconds = minVoicedSeconds
        self.maxSegmentSeconds = maxSegmentSeconds
        self.forcedSearchSeconds = forcedSearchSeconds
        self.tailPadSeconds = tailPadSeconds
        self.energyThreshold = energyThreshold
        self.peakRatio = peakRatio
        self.floor = floor
        self.windowSamples = max(1, Int(sampleRate * 0.02))
    }

    /// The level a window must reach to count as speech.
    var threshold: Float { max(floor, min(energyThreshold, peak * peakRatio)) }

    /// Analyzes every complete window of `samples` not yet seen and returns the new cuts, in
    /// order. `samples` is the whole dictation so far; earlier samples must not change.
    mutating func advance(over samples: [Float]) -> [Int] {
        var cuts: [Int] = []
        while (windowRMS.count + 1) * windowSamples <= samples.count {
            let start = windowRMS.count * windowSamples
            let end = start + windowSamples
            var sumSquares: Float = 0
            for i in start..<end { sumSquares += samples[i] * samples[i] }
            let rms = (sumSquares / Float(windowSamples)).squareRoot()
            windowRMS.append(rms)
            peak = max(peak, rms)
            if rms >= threshold {
                voicedWindows += 1
                silentRun = 0
            } else {
                silentRun += 1
            }

            let hasSpeech = Double(voicedWindows * windowSamples) >= minVoicedSeconds * sampleRate
            if hasSpeech, Double(silentRun * windowSamples) >= pauseSeconds * sampleRate {
                let silenceStart = end - silentRun * windowSamples
                cut(at: min(end, silenceStart + Int(tailPadSeconds * sampleRate)), into: &cuts)
            } else if hasSpeech, Double(end - segmentStart) >= maxSegmentSeconds * sampleRate {
                cut(at: quietestPoint(before: end), into: &cuts)
            }
        }
        return cuts
    }

    /// Seconds of speech in `range`, by the current threshold. The stream's gate for the tail
    /// left at release, which no pause rule has vetted.
    func voicedSeconds(in range: Range<Int>) -> Double {
        let first = (range.lowerBound + windowSamples - 1) / windowSamples
        let last = min(windowRMS.count, range.upperBound / windowSamples)
        guard first < last else { return 0 }
        let gate = threshold
        let voiced = windowRMS[first..<last].filter { $0 >= gate }.count
        return Double(voiced * windowSamples) / sampleRate
    }

    private mutating func cut(at index: Int, into cuts: inout [Int]) {
        cuts.append(index)
        segmentStart = index
        // Recount the windows already seen past the cut: they open the next segment.
        voicedWindows = 0
        silentRun = 0
        let gate = threshold
        for rms in windowRMS[min(windowRMS.count, index / windowSamples)...] {
            if rms >= gate { voicedWindows += 1; silentRun = 0 } else { silentRun += 1 }
        }
    }

    // The middle of the quietest 100 ms span in the last `forcedSearchSeconds` before `end`.
    private func quietestPoint(before end: Int) -> Int {
        let span = 5
        let endWindow = end / windowSamples
        let searchStart = max(segmentStart / windowSamples + 1, endWindow - Int(forcedSearchSeconds * sampleRate) / windowSamples)
        guard searchStart + span <= endWindow else { return end }
        var best = searchStart
        var bestSum = Float.greatestFiniteMagnitude
        for k in searchStart...(endWindow - span) {
            let sum = windowRMS[k..<(k + span)].reduce(0, +)
            if sum < bestSum { bestSum = sum; best = k }
        }
        return best * windowSamples + span * windowSamples / 2
    }
}
