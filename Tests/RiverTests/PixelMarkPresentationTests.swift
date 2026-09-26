import Foundation
import Testing
@testable import River

// The `inputLevel` a microphone reading of this many decibels of full scale publishes.
func inputLevel(decibels: Double) -> Double {
    pow(10, decibels / 20) / Double(Constants.inputLevelReferenceRMS)
}

// Rough loudness at a built-in mic: quiet talking, normal speech.
let quietSpeechDecibels = -42.0
let speechDecibels = -32.0

// Steps a frame at 60 fps, the way the indicator's TimelineView does.
extension PixelMarkFrame {
    func running(_ activity: PixelMarkActivity, from start: Double, for seconds: Double, reduceMotion: Bool = false,
                 level: (Double) -> Double = { _ in 0 }) -> (frame: PixelMarkFrame, end: Double) {
        var frame = self
        var now = start
        while now < start + seconds - 1e-9 {
            now += 1.0 / 60
            frame = frame.advanced(to: now, activity: activity, inputLevel: level(now), reduceMotion: reduceMotion)
        }
        return (frame, now)
    }
}

@Suite("PixelMarkPresentation")
struct PixelMarkPresentationTests {
    typealias Mark = PixelMarkPresentation

    @Test("the ease-out runs from 0 to 1 without turning back")
    func easeOutShape() {
        #expect(Mark.easeOut(0) == 0)
        #expect(Mark.easeOut(1) == 1)
        let samples = (0...100).map { Mark.easeOut(Double($0) / 100) }
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }

    // The drop answers the key press rather than trailing it.
    @Test("three quarters of the travel happens in the first quarter of the time")
    func easeOutIsFrontLoaded() {
        #expect(Mark.easeOut(0.25) >= 0.75)
    }

    @Test("the crest is full at its center and dark at the edge of its window")
    func crestWindow() {
        let half = Constants.pixelCrestHalfWidth
        #expect(Mark.crest(at: 0.5, position: 0.5 + half) == 1)
        #expect(Mark.crest(at: 0.5 + half, position: 0.5 + half) == 0)
        #expect(Mark.crest(at: 0, position: 1 + half) == 0)
    }

    // A pass enters fully before the stem's foot and leaves fully past the tip, so the loop
    // wrapping never makes a pixel jump.
    @Test("each crest pass enters and leaves the stroke fully", arguments: [0.0, 0.5, 1.0])
    func crestLoopNeverPops(fraction: Double) {
        #expect(Mark.crestLoop(at: fraction, since: 0) == 0)
        #expect(Mark.crestLoop(at: fraction, since: Constants.pixelCrestPeriod - 1e-9) < 1e-6)
    }

    @Test("the crest reaches the stem's foot before the shoulder and the tip")
    func crestRunsTheStroke() {
        func peakTime(_ fraction: Double) -> Double {
            let times = (0..<200).map { Double($0) / 100 }
            return times.max { Mark.crestLoop(at: fraction, since: $0) < Mark.crestLoop(at: fraction, since: $1) } ?? 0
        }
        #expect(peakTime(0) < peakTime(0.5))
        #expect(peakTime(0.5) < peakTime(1))
    }

    @Test("frames advance by at most 50 ms so a resumed timeline does not leap")
    func frameIntervalIsCapped() {
        #expect(Mark.frameInterval(from: nil, to: 10) == 0)
        #expect(abs(Mark.frameInterval(from: 10, to: 10.016) - 0.016) < 1e-9)
        #expect(Mark.frameInterval(from: 10, to: 70) == Constants.pixelMaxFrameInterval)
    }

    @Test("loudness is silent at and below the floor and full at the ceiling")
    func loudnessRange() {
        #expect(Mark.loudness(level: 0) == 0)
        #expect(Mark.loudness(level: inputLevel(decibels: Constants.pixelMeterFloorDecibels - 6)) == 0)
        #expect(abs(Mark.loudness(level: inputLevel(decibels: Constants.pixelMeterCeilingDecibels)) - 1) < 1e-9)
        #expect(Mark.loudness(level: 1) == 1)
        let samples = stride(from: -70.0, through: -20, by: 1).map { Mark.loudness(level: inputLevel(decibels: $0)) }
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }

    // A meter that moved for a recording the capture trim then discards as silence would
    // claim River heard words it threw away.
    @Test("the meter stays dark for audio the capture trim treats as silence")
    func meterFloorIsTheTrimGate() {
        let trimFloorDecibels = 20 * log10(Double(Constants.silenceTrimEnergyThreshold))
        #expect(Mark.loudness(level: inputLevel(decibels: trimFloorDecibels - 1)) == 0)
        #expect(Mark.loudness(level: inputLevel(decibels: trimFloorDecibels + 3)) > 0)
    }

    // Preparing belongs to idle only: the model is ready before a recording can start, and a
    // failed load stays in the menu (no mark on screen for an unrecoverable state).
    @Test("the mark prepares only at idle while the model gets ready", arguments: [
        (RiverState.idle, true, PixelMarkActivity.preparing),
        (RiverState.idle, false, PixelMarkActivity.rest),
        (RiverState.recording, true, PixelMarkActivity.listening),
        (RiverState.recording, false, PixelMarkActivity.listening),
        (RiverState.processing, false, PixelMarkActivity.transcribing),
    ])
    func activityMapping(state: RiverState, isModelPreparing: Bool, expected: PixelMarkActivity) {
        #expect(PixelMarkActivity.of(state: state, isModelPreparing: isModelPreparing) == expected)
    }

    @Test("Increase Contrast lifts dim cells and leaves bright ones alone")
    func increaseContrastFloor() {
        #expect(Mark.displayInk(Constants.pixelUnlitInk, increaseContrast: true) == Constants.pixelIncreasedContrastInkFloor)
        #expect(Mark.displayInk(Constants.pixelUnlitInk, increaseContrast: false) == Constants.pixelUnlitInk)
        #expect(Mark.displayInk(Constants.pixelLitInk, increaseContrast: true) == Constants.pixelLitInk)
    }
}

@Suite("PixelMarkFrame")
struct PixelMarkFrameTests {
    static let start = 1_000.0

    static func meanHeight(of frame: PixelMarkFrame) -> Double {
        frame.bars.map(\.height).reduce(0, +) / Double(frame.bars.count)
    }

    @Test("at rest the mark is the r at full ink, untinted and in place")
    func restIsTheR() {
        let (frame, _) = PixelMarkFrame(seed: 1).running(.rest, from: Self.start, for: 0.5)
        for index in PixelMark.cells.indices {
            #expect(frame.ink[index] == 1)
            #expect(frame.accentMix[index] == 0)
            let offset = frame.offset(ofCell: index)
            #expect(offset.x == 0 && offset.y == 0)
        }
        #expect(frame.opacity == 1)
    }

    @Test("listening drops every pixel onto its meter slot within the drop time")
    func dropLandsOnTheMeter() {
        let (frame, _) = PixelMarkFrame(seed: 1).running(.listening, from: Self.start, for: Constants.pixelDropSeconds + 0.02)
        for (index, cell) in PixelMark.cells.enumerated() {
            let offset = frame.offset(ofCell: index)
            #expect(offset.x == Double(cell.meterX - cell.x))
            #expect(offset.y == Double(cell.meterY - cell.y))
        }
    }

    // A new state retargets from where the pixels are, so an interrupted drop never jumps.
    @Test("an interrupted drop turns back from where the pixels are")
    func interruptionIsContinuous() {
        let (dropping, now) = PixelMarkFrame(seed: 1).running(.listening, from: Self.start, for: 0.1)
        let before = PixelMark.cells.indices.map { dropping.offset(ofCell: $0) }
        #expect(before.contains { $0.x != 0 || $0.y != 0 })
        let turned = dropping.advanced(to: now + 1e-4, activity: .transcribing, inputLevel: 0, reduceMotion: false)
        for index in PixelMark.cells.indices {
            let after = turned.offset(ofCell: index)
            #expect(abs(after.x - before[index].x) < 0.01 && abs(after.y - before[index].y) < 0.01)
        }
    }

    @Test("transcribing returns every pixel to the r, then runs the crest in ink")
    func transcribingReturnsToTheR() {
        let (listening, now) = PixelMarkFrame(seed: 1).running(.listening, from: Self.start, for: 1) { _ in 0.8 }
        let (frame, _) = listening.running(.transcribing, from: now, for: Constants.pixelReturnSeconds + 0.6)
        for index in PixelMark.cells.indices {
            let offset = frame.offset(ofCell: index)
            #expect(offset.x == 0 && offset.y == 0)
            #expect(frame.accentMix[index] < 0.01)
            #expect(frame.ink[index] > Constants.pixelCrestBase - 0.02)
        }
        #expect((frame.ink.max() ?? 0) > Constants.pixelCrestBase + 0.2)
    }

    // Silence keeps a half-lit bottom row, so a quiet listening state never looks like rest.
    @Test("in silence every column settles to the pilot")
    func silenceSettlesToThePilot() {
        let (frame, _) = PixelMarkFrame(seed: 3).running(.listening, from: Self.start, for: 2)
        for bar in frame.bars {
            #expect(abs(bar.height - Constants.pixelMeterPilot) < 0.01)
        }
    }

    static func averageHeight(level: Double) -> Double {
        var frame = PixelMarkFrame(seed: 5)
        var now = start, total = 0.0, count = 0
        for step in 0..<240 {
            now += 1.0 / 60
            frame = frame.advanced(to: now, activity: .listening, inputLevel: level, reduceMotion: false)
            if step >= 60 {
                total += meanHeight(of: frame)
                count += 1
            }
        }
        return total / Double(count)
    }

    @Test("louder speech raises the meter")
    func louderIsTaller() {
        #expect(Self.averageHeight(level: inputLevel(decibels: speechDecibels))
            > Self.averageHeight(level: inputLevel(decibels: quietSpeechDecibels)) + 0.8)
    }

    // Each column is its own readout: while speaking they stand at different heights.
    @Test("while speaking the columns move out of step")
    func columnsAreIndependent() {
        var frame = PixelMarkFrame(seed: 7)
        var now = Self.start, spread = 0.0, count = 0
        for step in 0..<300 {
            now += 1.0 / 60
            frame = frame.advanced(to: now, activity: .listening, inputLevel: inputLevel(decibels: speechDecibels), reduceMotion: false)
            if step >= 60 {
                let heights = frame.bars.map(\.height)
                spread += (heights.max() ?? 0) - (heights.min() ?? 0)
                count += 1
            }
        }
        #expect(spread / Double(count) > 0.8)
    }

    @Test("under Reduce Motion the columns move together")
    func reduceMotionColumnsMoveTogether() {
        let (frame, _) = PixelMarkFrame(seed: 7).running(.listening, from: Self.start, for: 1, reduceMotion: true) { _ in 0.8 }
        #expect(frame.bars[0].height == frame.bars[3].height)
        #expect(frame.bars[1].height == frame.bars[2].height)
        #expect(frame.bars[1].height > Constants.pixelMeterPilot + 1)
    }

    // Reduce Motion never moves a pixel through space: the layout swaps at the bottom of a dip.
    @Test("under Reduce Motion pixels swap layouts inside a dip instead of travelling")
    func reduceMotionHasNoTravel() {
        var frame = PixelMarkFrame(seed: 1)
        var now = Self.start, dipped = false
        for _ in 0..<60 {
            now += 1.0 / 60
            frame = frame.advanced(to: now, activity: .listening, inputLevel: 0, reduceMotion: true)
            for (index, cell) in PixelMark.cells.enumerated() {
                let offset = frame.offset(ofCell: index)
                let home = offset.x == 0 && offset.y == 0
                let slot = offset.x == Double(cell.meterX - cell.x) && offset.y == Double(cell.meterY - cell.y)
                #expect(home || slot)
            }
            if frame.opacity < 0.2 { dipped = true }
        }
        #expect(dipped)
        #expect(frame.opacity == 1)
    }

    @Test("under Reduce Motion transcribing is the dithered r, as in the menu bar")
    func reduceMotionTranscribingIsDithered() {
        let (listening, now) = PixelMarkFrame(seed: 1).running(.listening, from: Self.start, for: 0.5, reduceMotion: true)
        let (frame, _) = listening.running(.transcribing, from: now, for: 1, reduceMotion: true)
        for (index, cell) in PixelMark.cells.enumerated() {
            #expect(abs(frame.ink[index] - PixelMark.ditherInk(cell)) < 0.01)
        }
    }

    // Preparing replaces the spinner: the r in place, in ink, with a slow crest over a dimmer
    // base than transcribing, so waiting never reads as working on your words.
    @Test("preparing keeps the r in place and runs a slow ink crest over a dim base")
    func preparingIsAWaitingR() {
        let (frame, _) = PixelMarkFrame(seed: 1).running(.preparing, from: Self.start, for: Constants.pixelPreparingCrestPeriod)
        for index in PixelMark.cells.indices {
            let offset = frame.offset(ofCell: index)
            #expect(offset.x == 0 && offset.y == 0)
            #expect(frame.accentMix[index] == 0)
            #expect(frame.ink[index] > Constants.pixelPreparingCrestBase - 0.02)
        }
        #expect((frame.ink.min() ?? 1) < Constants.pixelCrestBase)
        #expect(Constants.pixelPreparingCrestPeriod > Constants.pixelCrestPeriod)
    }

    @Test("under Reduce Motion preparing is the dithered r")
    func reduceMotionPreparingIsDithered() {
        let (frame, _) = PixelMarkFrame(seed: 1).running(.preparing, from: Self.start, for: 1, reduceMotion: true)
        for (index, cell) in PixelMark.cells.enumerated() {
            #expect(abs(frame.ink[index] - PixelMark.ditherInk(cell)) < 0.01)
        }
    }

    @Test("the same seed gives the same meter")
    func seededFramesRepeat() {
        let level: (Double) -> Double = { 0.5 + 0.3 * sin($0 * 7) }
        let first = PixelMarkFrame(seed: 9).running(.listening, from: Self.start, for: 2, level: level).frame
        let second = PixelMarkFrame(seed: 9).running(.listening, from: Self.start, for: 2, level: level).frame
        #expect(first == second)
    }
}
