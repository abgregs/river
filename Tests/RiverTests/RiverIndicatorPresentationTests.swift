import Testing
@testable import River

@Suite("River indicator constants")
struct RiverIndicatorConstantsTests {
    // The capsule is the strands' full range of motion plus padding and never changes
    // size (identity-studies: empty and filled states are the same size).
    @Test("the capsule is the 108 x 40 mark plus 12 pt at the sides and 8 pt above and below")
    func capsuleGeometry() {
        #expect(Constants.riverMarkWidth == 108)
        #expect(Constants.riverMarkHeight == 40)
        #expect(Constants.riverCapsuleWidth == 132)
        #expect(Constants.riverCapsuleHeight == 56)
        #expect(Constants.riverCapsuleCornerRadius == 28)
    }

    // Concentric radii: the message rectangle's radius is its padding plus a 4 pt inner radius.
    @Test("the message rectangle keeps the concentric 16 pt radius over 12 pt padding")
    func messageGeometry() {
        #expect(Constants.hudMessageCornerRadius == Constants.hudMessagePadding + 4)
        #expect(Constants.hudStackSpacing == 8)
    }

    @Test("the fade is 0.22 s with a 6 pt rise")
    func fade() {
        #expect(Constants.hudFadeSeconds == 0.22)
        #expect(Constants.hudFadeRise == 6)
    }

    // An even stop count would put no stop at the crest's peak, flattening its top.
    @Test("the crest window has an odd stop count so one stop sits on the peak")
    func crestStops() {
        #expect(Constants.riverCrestStopCount == 17)
        #expect(Constants.riverCrestStopCount % 2 == 1)
    }

    @Test("three strands, the middle one widest and at full ink")
    func strandTable() {
        let strands = Constants.riverStrands
        #expect(strands.count == 3)
        #expect(strands.map(\.baseY) == [11.5, 20, 28.5])
        #expect(strands[1].width == strands.map(\.width).max())
        #expect(strands[1].ink == 1)
    }

    // Snapping rows per scale is what makes the 16 pt template glyph crisp; a center
    // off the pixel grid would antialias every slat across two rows.
    @Test("glyph rows sit on pixel centers at 1x and pixel boundaries at 2x")
    func glyphRowSnapping() {
        #expect(Constants.menuBarGlyphRowCenters1x.allSatisfy { ($0 - 0.5).truncatingRemainder(dividingBy: 1) == 0 })
        #expect(Constants.menuBarGlyphRowCenters2x.allSatisfy { ($0 * 2).truncatingRemainder(dividingBy: 1) == 0 })
        #expect(Constants.menuBarGlyphRowInsets.count == 5)
        #expect(Constants.menuBarGlyphDotCounts == [3, 4, 5, 4, 3])
    }
}

@Suite("RiverIndicatorPresentation")
struct RiverIndicatorPresentationTests {
    private typealias River = RiverIndicatorPresentation
    private let strands = Constants.riverStrands

    // Reference values below were produced by running the study page's own river
    // block (riverY, smoothstep, the crest stops and translation) in node, so these
    // tests pin the port to the approved reference, not to itself.
    @Test("strand y matches the study page at known inputs", arguments: [
        (0, 0.0, 0.35, 0.0, 13.31205117240021),
        (1, 0.5, 1.0, 3.7, 14.977993049935773),
        (2, 0.25, 0.4, 10.0, 30.074906974670636),
        (0, 1.0, 0.62, -2.0, 12.663170411697644),
    ])
    func strandY(index: Int, u: Double, motion: Double, clock: Double, expected: Double) {
        let y = River.strandY(strands[index], fraction: u, motion: motion, clock: clock)
        #expect(abs(y - expected) < 1e-9)
    }

    @Test("a strand is sampled at 57 points spanning the 108 pt mark")
    func strandSampling() {
        let points = River.strandPoints(strands[1], motion: 0.5, clock: 1)
        #expect(points.count == 57)
        #expect(points.first?.x == 0)
        #expect(points.last?.x == 108)
    }

    @Test("rest, live input, and transcribing each set the level the strands chase")
    func targetLevel() {
        #expect(River.targetLevel(state: .idle, inputLevel: 0.9) == 0)
        #expect(River.targetLevel(state: .recording, inputLevel: 0.62) == 0.62)
        #expect(River.targetLevel(state: .recording, inputLevel: 1.4) == 1)
        #expect(River.targetLevel(state: .processing, inputLevel: 0.9) == 0.4)
    }

    // Round two's timing: attack at 10 per second, release at 5. A slower attack read as
    // sluggish and a sharper one "far too snappy" (identity-studies, rejected table).
    @Test("the level rises at the attack rate and falls at the release rate")
    func smoothingRates() {
        #expect(abs(River.smoothedLevel(current: 0, target: 1, frameInterval: 0.02) - 0.2) < 1e-12)
        #expect(abs(River.smoothedLevel(current: 1, target: 0, frameInterval: 0.02) - 0.9) < 1e-12)
        // A long frame lands on the target instead of overshooting it.
        #expect(River.smoothedLevel(current: 0, target: 1, frameInterval: 0.5) == 1)
    }

    // Below the floor the strands would wobble sub-pixel and read as grain.
    @Test("motion never falls below the level-0.35 shape", arguments: [
        (0.0, 0.35), (0.2, 0.35), (0.35, 0.35), (0.7, 0.7), (1.0, 1.0),
    ])
    func motionFloor(level: Double, expected: Double) {
        #expect(River.motion(level: level) == expected)
    }

    @Test("ink progress is a smoothstep over the first half of the level range", arguments: [
        (0.0, 0.0), (0.1, 0.104), (0.25, 0.5), (0.5, 1.0), (0.8, 1.0),
    ])
    func inkProgress(level: Double, expected: Double) {
        #expect(abs(River.inkProgress(level: level) - expected) < 1e-12)
    }

    // The water never stops: at rest the clock still runs at 45% of real time.
    @Test("the strand clock runs at 45% at rest and full speed once awake", arguments: [
        (0.0, 0.45), (0.25, 0.725), (0.5, 1.0), (1.0, 1.0),
    ])
    func clockRate(level: Double, expected: Double) {
        #expect(abs(River.clockRate(level: level) - expected) < 1e-12)
    }

    @Test("rest ink breathes around 44% and holds still under Reduce Motion")
    func restInk() {
        #expect(River.restInk(time: 0, reduceMotion: false) == 0.44)
        let peak = Double.pi / 2 / 0.9
        #expect(abs(River.restInk(time: peak, reduceMotion: false) - 0.50) < 1e-12)
        #expect(River.restInk(time: peak, reduceMotion: true) == 0.44)
    }

    @Test("a strand's opacity runs from rest ink to its own ink as the level wakes")
    func strandOpacity() {
        #expect(River.strandOpacity(strands[2], level: 0, time: 0, reduceMotion: true) == 0.44)
        #expect(abs(River.strandOpacity(strands[2], level: 0.5, time: 0, reduceMotion: true) - 0.55) < 1e-12)
        #expect(abs(River.strandOpacity(strands[0], level: 0.25, time: 0, reduceMotion: true) - 0.57) < 1e-12)
    }

    @Test("stroke width grows by 0.8 per unit of motion from its floor")
    func strandWidth() {
        #expect(abs(River.strandWidth(strands[1], level: 0) - 2.88) < 1e-12)
        #expect(abs(River.strandWidth(strands[1], level: 1) - 3.4) < 1e-12)
    }

    @Test("the crest window is flat at full ink while listening and a raised cosine over 55% while transcribing")
    func crestWindow() {
        #expect(River.crestStopOpacities(base: 1).allSatisfy { $0 == 1 })
        let crest = River.crestStopOpacities(base: River.crestBase(blend: 1))
        #expect(crest.count == 17)
        #expect(abs(crest[0] - 0.55) < 1e-12 && abs(crest[16] - 0.55) < 1e-12)
        #expect(abs(crest[8] - 1) < 1e-12)
        #expect(abs(crest[4] - 0.775) < 1e-12)
        #expect(abs(crest[1] - 0.5671271051849606) < 1e-12)
    }

    @Test("the crest crosses from -70 to 178 pt once per 2 s, each strand offset by 0.18", arguments: [
        (0.0, 0, -70.0), (1.0, 0, 54.0), (0.5, 2, 81.28), (3.1, 1, 111.04),
    ])
    func crestOffset(time: Double, strand: Int, expected: Double) {
        #expect(abs(River.crestOffset(time: time, strandIndex: strand) - expected) < 1e-9)
    }

    // Color alone never carries the state: under Reduce Motion there is no crest, so
    // transcribing must fall back to the calm lines at full ink rather than a dim base.
    @Test("the crest blends in only while transcribing and never under Reduce Motion")
    func crestBlend() {
        #expect(River.crestBlendTarget(state: .processing, reduceMotion: false) == 1)
        #expect(River.crestBlendTarget(state: .recording, reduceMotion: false) == 0)
        #expect(River.crestBlendTarget(state: .processing, reduceMotion: true) == 0)
        #expect(abs(River.crestBlend(current: 0, target: 1, frameInterval: 0.05, reduceMotion: false) - 0.6) < 1e-12)
        #expect(River.crestBlend(current: 0.6, target: 0, frameInterval: 0.01, reduceMotion: true) == 0)
    }

    @Test("frames advance by at most 50 ms so a resumed timeline does not leap")
    func frameInterval() {
        #expect(River.frameInterval(from: nil, to: 10) == 0)
        #expect(abs(River.frameInterval(from: 10, to: 10.016) - 0.016) < 1e-9)
        #expect(River.frameInterval(from: 10, to: 42) == 0.05)
    }

    @Test("a frame advances level, clock, and crest together toward the transcribing state")
    func frameAdvance() {
        var frame = RiverIndicatorFrame().advanced(to: 100, state: .processing, inputLevel: 0, reduceMotion: false)
        #expect(frame.level == 0 && frame.clock == 0)
        frame = frame.advanced(to: 100.05, state: .processing, inputLevel: 0, reduceMotion: false)
        #expect(abs(frame.level - 0.2) < 1e-12)
        #expect(abs(frame.clock - 0.05 * River.clockRate(level: 0.2)) < 1e-12)
        #expect(abs(frame.crestBlend - 0.6) < 1e-12)
    }
}
