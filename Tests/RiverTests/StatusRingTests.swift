import Foundation
import Testing
@testable import River

@Suite("Status ring")
struct StatusRingTests {
    // planning 0004 and the preparing status study, round ten: the arc shows the real download
    // fraction, a light turns while the model gets ready, a check when it's ready, and akane with
    // an exclamation mark when it couldn't load. Each test pins one moment of the spec table.

    @Test("the arc glides through each rise of the real fraction on a spring that never overshoots, settled in about 0.6 s")
    func arcGlides() {
        var events = StatusRingEvents(appearing: .downloading, fraction: 0.2)
        events.record(fraction: 0.5, at: 1)
        let q = { StatusRing.fraction(at: $0, events: events)! }
        #expect(q(1) == 0.2)
        #expect(abs(q(1.6) - 0.5) < 0.03)
        // A burst of progress never makes the arc jump, run past the real fraction, or come back.
        let samples = stride(from: 1.0, through: 4, by: 0.01).map(q)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(samples.allSatisfy { $0 <= 0.5 })
    }

    @Test("a lower fraction records nothing, so the arc never runs back")
    func arcNeverRunsBack() {
        var events = StatusRingEvents(appearing: .downloading, fraction: 0.2)
        events.record(fraction: 0.6, at: 1)
        let before = events
        events.record(fraction: 0.4, at: 1.2)
        #expect(events == before)
    }

    @Test("steps that have settled fold into the base, so a long download keeps a short sum")
    func settledStepsFold() {
        var events = StatusRingEvents(appearing: .downloading, fraction: 0)
        for i in 1...200 { events.record(fraction: Double(i) / 200, at: Double(i) * 0.5) }
        #expect(events.steps.count <= 5)
        #expect(abs(StatusRing.fraction(at: 200, events: events)! - 1) < 0.001)
    }

    @Test("a different model starts the ring again at its own fraction, so a switch never glides backward")
    func switchStartsAgain() {
        let start = Date(timeIntervalSince1970: 0)
        var cycle = StatusRingCycle.next(nil, phase: .downloading, model: "a", fraction: 0.8, at: start)
        cycle = StatusRingCycle.next(cycle, phase: .downloading, model: "b", fraction: 0.1, at: start.addingTimeInterval(3))
        #expect(cycle.model == "b")
        let frame = StatusRing.frame(at: cycle.time(at: start.addingTimeInterval(3.05)), events: cycle.events, reduceMotion: false)
        #expect(Self.arc(frame) == 0.1)
    }

    @Test("once failed the ring holds, and a phase it has passed is not shown again")
    func phasesOnlyMoveOn() {
        let start = Date(timeIntervalSince1970: 0)
        var cycle = StatusRingCycle.next(nil, phase: .downloading, model: "a", fraction: 0.3, at: start)
        cycle = StatusRingCycle.next(cycle, phase: .preparing, model: "a", fraction: nil, at: start.addingTimeInterval(1))
        // A cached model that won't load downloads again; the ring stays on preparing.
        cycle = StatusRingCycle.next(cycle, phase: .downloading, model: "a", fraction: 0.5, at: start.addingTimeInterval(2))
        cycle = StatusRingCycle.next(cycle, phase: .failed, model: "a", fraction: nil, at: start.addingTimeInterval(3))
        // Try Again while the failure shows: the ring keeps saying what happened.
        cycle = StatusRingCycle.next(cycle, phase: .preparing, model: "a", fraction: nil, at: start.addingTimeInterval(4))
        #expect(cycle.events.preparing == 1)
        #expect(cycle.events.failed == 3)
        #expect(cycle.events.target == 0.3)
    }

    @Test("while downloading the head dims by a fifth and back every 2.8 s; under Reduce Motion it holds")
    func headBreathes() {
        let events = StatusRingEvents(appearing: .downloading, fraction: 0.5)
        let head = { (t: Double, reduceMotion: Bool) in Self.head(StatusRing.frame(at: t, events: events, reduceMotion: reduceMotion))! }
        #expect(Self.close(head(0, false), StatusRing.over(0.9, 0.45)))
        #expect(Self.close(head(1.4, false), StatusRing.over(0.7, 0.45)))
        #expect(Self.close(head(2.8, false), StatusRing.over(0.9, 0.45)))
        #expect(Self.close(head(1.4, true), StatusRing.over(0.9, 0.45)))
    }

    @Test("the closed arc hands over to the turning light in 0.6 s, closing as it goes")
    func handOff() {
        var events = StatusRingEvents(appearing: .downloading, fraction: 0.97)
        events.preparing = 2
        let at = { StatusRing.frame(at: $0, events: events, reduceMotion: false) }
        #expect(at(2).layers.map(\.opacity) == [1, 0])
        let mid = at(2.3).layers.map(\.opacity)
        #expect(Self.close(mid[0], 0.5, 0.01) && Self.close(mid[1], 0.5, 0.01))
        #expect(Self.arc(at(2.3))! > 0.97)
        #expect(at(2.6).layers.count == 1)
        #expect(Self.light(at(2.6)) == 1)
    }

    @Test("the light starts from rest at the top and turns once every 2.4 s from 0.8 s")
    func lightTurns() {
        let speed = 2 * Double.pi / 2.4
        #expect(StatusRing.lightAngle(0) == 0)
        #expect(Self.close(StatusRing.lightAngle(0.8), 0.4 * speed))
        #expect(Self.close(StatusRing.lightAngle(3.2) - StatusRing.lightAngle(0.8), 2 * .pi))
        #expect(StatusRing.lightAngle(0.1) < StatusRing.lightAngle(1.1) - StatusRing.lightAngle(1.0))
    }

    @Test("ready: the ring rises to 90 % over 0.45 s, the light fades over 0.35 s, the check comes in from 0.15 s over 0.4 s")
    func readyChecks() {
        var events = StatusRingEvents(appearing: .preparing, fraction: nil)
        events.ready = 3
        let at = { StatusRing.frame(at: $0, events: events, reduceMotion: false) }
        #expect(Self.close(Self.rings(at(3)).last!, 0.45))
        #expect(Self.close(Self.rings(at(3.45)).last!, 0.9))
        #expect(Self.close(Self.light(at(3.35))!, 0))
        #expect(Self.close(Self.check(at(3.15))!.progress, 0))
        #expect(Self.close(Self.check(at(3.55))!.progress, 1))
        #expect(Self.check(at(3.3))!.wipes)
        #expect(at(3.3).akane == 0)
    }

    @Test("a download that fails stops breathing, turns akane where it stands, then shows its sign, 1.3 s in all")
    func failedDownload() {
        var events = StatusRingEvents(appearing: .downloading, fraction: 0.62)
        events.failed = 1.4   // the head at its dimmest
        let at = { StatusRing.frame(at: $0, events: events, reduceMotion: false) }
        #expect(Self.close(Self.head(at(1.4))!, StatusRing.over(0.7, 0.45)))
        #expect(Self.close(Self.head(at(1.65))!, StatusRing.over(0.9, 0.45)))
        #expect(Self.close(at(1.75).akane, 0))
        #expect(Self.close(at(2.25).akane, 1))
        #expect(Self.close(Self.exclamation(at(2.25))!.progress, 0))
        #expect(Self.close(Self.exclamation(at(2.7))!.progress, 1))
        #expect(Self.arc(at(2.7)) == 0.62)
    }

    @Test("a load that fails after the download shows the whole ring at 62 %, the light stopped")
    func failedAfterDownload() {
        var events = StatusRingEvents(appearing: .preparing, fraction: nil)
        events.failed = 2
        let done = StatusRing.frame(at: 3.4, events: events, reduceMotion: false)
        #expect(Self.close(Self.rings(done).first!, 0.62))
        #expect(done.akane == 1)
        #expect(Self.exclamation(done)!.progress == 1)
        #expect(Self.close(Self.light(done)!, 0))
        #expect(Self.arc(done) == nil)
    }

    @Test("a ring that appears failed shows its sign at once: the arc where the download stopped, or the whole ring after it")
    func appearsFailed() {
        let during = StatusRing.frame(at: 0, events: StatusRingEvents(appearing: .failed, fraction: 0.4), reduceMotion: false)
        #expect(Self.arc(during) == 0.4)
        #expect(during.akane == 1)
        #expect(Self.exclamation(during)!.progress == 1)
        let after = StatusRing.frame(at: 0, events: StatusRingEvents(appearing: .failed, fraction: nil), reduceMotion: false)
        #expect(Self.arc(after) == nil)
        #expect(Self.rings(after) == [0.62])
    }

    @Test("a ring that appears ready shows its check at once, since Settings opens long after the load")
    func appearsReady() {
        let ready = StatusRing.frame(at: 0, events: StatusRingEvents(appearing: .ready, fraction: nil), reduceMotion: false)
        #expect(Self.rings(ready) == [0.9])
        #expect(Self.check(ready)!.progress == 1)
        #expect(ready.akane == 0)
    }

    @Test("under Reduce Motion nothing travels: preparing pulses between 45 % and 62 % every 2.8 s, and every change is a 0.2 s fade")
    func reduceMotion() {
        let preparing = StatusRingEvents(appearing: .preparing, fraction: nil)
        let at = { StatusRing.frame(at: $0, events: preparing, reduceMotion: true) }
        #expect(Self.light(at(1)) == nil)
        #expect(Self.close(Self.rings(at(0)).first!, 0.45))
        #expect(Self.close(Self.rings(at(1.4)).first!, 0.62))
        var ready = preparing
        ready.ready = 2.8
        let readyAt = { StatusRing.frame(at: $0, events: ready, reduceMotion: true) }
        #expect(Self.close(Self.rings(readyAt(3)).last!, 0.9))
        let check = Self.check(readyAt(3.05))!
        #expect(Self.close(check.progress, 0.5))
        #expect(!check.wipes)
    }

    // MARK: - Reading a frame

    private static func marks(_ frame: StatusRingFrame) -> [StatusRingFrame.Mark] { frame.layers.flatMap(\.marks) }

    private static func arc(_ frame: StatusRingFrame) -> Double? {
        marks(frame).lazy.compactMap { if case .arc(let fraction, _) = $0 { fraction } else { nil } }.first
    }

    private static func head(_ frame: StatusRingFrame) -> Double? {
        marks(frame).lazy.compactMap { if case .head(_, let alpha) = $0 { alpha } else { nil } }.first
    }

    // Every whole ring's alpha, in drawing order.
    private static func rings(_ frame: StatusRingFrame) -> [Double] {
        marks(frame).compactMap { if case .ring(let alpha) = $0 { alpha } else { nil } }
    }

    // The opacity of the layer holding preparing's light, or nil with no light.
    private static func light(_ frame: StatusRingFrame) -> Double? {
        frame.layers.first { $0.marks.contains { if case .light = $0 { true } else { false } } }?.opacity
    }

    private static func check(_ frame: StatusRingFrame) -> StatusRingFrame.Reveal? {
        marks(frame).lazy.compactMap { if case .check(let reveal) = $0 { reveal } else { nil } }.first
    }

    private static func exclamation(_ frame: StatusRingFrame) -> StatusRingFrame.Reveal? {
        marks(frame).lazy.compactMap { if case .exclamation(let reveal) = $0 { reveal } else { nil } }.first
    }

    private static func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }
}
