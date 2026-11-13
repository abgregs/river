import Foundation
import Testing
@testable import River

@Suite("ShortcutChip")
struct ShortcutChipTests {
    @Test("the halo starts at the dot, widens and fades over 70 % of each period, then rests")
    func haloCycle() {
        // One ring at a time, gone before the next begins, reads as live without pulling the
        // eye (shortcut recorder study, round 4).
        let period = Constants.recorderPulsePeriod
        let start = ShortcutChip.halo(at: 0)
        #expect(start.scale == 1)
        #expect(abs(start.opacity - Constants.recorderPulseOpacity) < 0.001)
        let rest = ShortcutChip.halo(at: 0.8 * period)
        #expect(rest.scale == Constants.recorderPulseScale && rest.opacity == 0)
        #expect(ShortcutChip.halo(at: period).scale == 1)
        let early = ShortcutChip.halo(at: 0.35 * period)
        #expect(early.scale > 2.2 && early.opacity < 0.15)
    }

    @Test("the halo's widest ring fits inside the recording outline")
    func haloFitsTheOutline() {
        // The 6 pt dot's ring must stay inside the 20 pt outline's 1 pt red edge, or the
        // outline clips it into a square.
        #expect(6 * Constants.recorderPulseScale <= 20 - 2)
    }

    @Test("the recorder settles a save only once its last stage has finished")
    func saveOutlastsItsStages() {
        // Settling sets the outline to its end at once; before a stage ends, that would cut it.
        #expect(Constants.recorderSaveSeconds >= Constants.recorderSaveDotDelay + Constants.recorderSaveDotDuration)
        #expect(Constants.recorderSaveSeconds >= Constants.recorderSaveOutlineDelay + Constants.recorderSaveOutlineDuration)
    }

    @Test("a shake moves the outline and comes to rest where it started")
    func shakeReturns() {
        // Each refusal shakes once; the outline must end exactly in place.
        func offset(_ value: Double) -> Double { RefusalShake(animatableData: value).effectValue(size: .zero).m31 }
        #expect(offset(0) == 0)
        #expect(offset(0.2) == -4)
        #expect(offset(0.4) == 4)
        #expect(offset(1) == 0)
    }
}
