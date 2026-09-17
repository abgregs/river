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
