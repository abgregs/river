import Carbon.HIToolbox
import Foundation
import Testing
@testable import River

@Suite("ShortcutRecorderModel")
@MainActor
struct ShortcutRecorderModelTests {
    private let controlOptionSpace = Shortcut.combination(keyCode: kVK_Space, modifiers: [.control, .option])

    private func press(_ model: ShortcutRecorderModel, _ keyCode: Int, with modifiers: ShortcutModifiers) {
        for code in [59, 58] where modifiers.contains(code == 59 ? .control : .option) {
            model.handle(.modifierChanged(keyCode: code, isDown: true))
        }
        model.handle(.keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: false))
    }

    @Test("recording pauses River's shortcuts, saves what it hears, and resumes them once keys are up")
    func recordsAndSaves() async throws {
        // While the recorder listens River's own shortcut must reach it, not start a dictation;
        // afterwards the new shortcut must work without reopening Settings.
        let log = HooksLog()
        let model = ShortcutRecorderModel(hooks: log.hooks)
        model.start()
        #expect(log.pauses == 1)
        #expect(model.phase == .recording)
        #expect(model.line == .recordingDictation)

        press(model, kVK_Space, with: [.control, .option])
        #expect(log.saved == [controlOptionSpace])
        #expect(model.phase == .saving(controlOptionSpace))
        #expect(model.line == nil)

        // The resume waits for every key to be up and a moment more; under a full parallel run
        // the main actor can be slow to get to it, so the test waits for it rather than a time.
        try await waitUntil { log.resumes == 1 && model.phase == .idle }
        #expect(log.resumes == 1)
        #expect(model.phase == .idle)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("a refused shortcut keeps recording, shows the attempt, and saves nothing")
    func refusalKeepsRecording() {
        // "Choose another" means press another: the next key press tries again (spec 0036).
        let log = HooksLog()
        log.registration = .takenByAnotherApp
        let model = ShortcutRecorderModel(hooks: log.hooks)
        model.start()
        press(model, kVK_Space, with: [.control, .option])
        #expect(log.saved.isEmpty)
        #expect(model.phase == .recording)
        #expect(model.tried == "⌃⌥Space")
        #expect(model.line == .refused("Another app uses this shortcut. Choose another."))
        #expect(model.refusals == 1)

        model.handle(.modifierChanged(keyCode: 59, isDown: false))
        model.handle(.modifierChanged(keyCode: 58, isDown: false))
        model.handle(.modifierChanged(keyCode: 62, isDown: true))
        #expect(model.tried == nil)
        #expect(model.line == .recordingDictation)
        model.stop()
    }

    @Test("fn is refused as River's cancel key")
    func fnRefused() {
        // The row's message names the row that owns it, which is on screen below.
        let log = HooksLog()
        let model = ShortcutRecorderModel(hooks: log.hooks)
        model.start()
        model.handle(.modifierChanged(keyCode: 63, isDown: true))
        model.handle(.modifierChanged(keyCode: 63, isDown: false))
        #expect(model.line == .refused("Cancel recording uses fn. Choose another."))
        #expect(log.saved.isEmpty)
        model.stop()
    }

    @Test("Delete can't clear the dictation shortcut, and Esc stops, keeping it")
    func deleteAndEscape() {
        // Dictation always needs a shortcut; Esc must leave the saved one exactly as it was.
        let log = HooksLog()
        let model = ShortcutRecorderModel(hooks: log.hooks)
        model.start()
        model.handle(.keyDown(keyCode: kVK_Delete, modifiers: [], isRepeat: false))
        #expect(model.line == .cannotClear)
        #expect(model.phase == .recording)
        model.handle(.keyDown(keyCode: kVK_Escape, modifiers: [], isRepeat: false))
        #expect(model.phase == .idle)
        #expect(log.saved.isEmpty)
    }

    @Test("a shortcut macOS also uses is saved, and its warning stays")
    func systemShortcutSavedWithWarning() {
        // Inform, don't block: the line stays as long as the clash is true.
        let log = HooksLog()
        log.system = [SystemShortcuts.Entry(keyCode: kVK_Space, modifiers: [.control, .option])]
        let model = ShortcutRecorderModel(hooks: log.hooks)
        model.start()
        press(model, kVK_Space, with: [.control, .option])
        #expect(log.saved == [controlOptionSpace])
        #expect(model.isSystemShortcut)
        model.refresh(saved: .modifier(keyCode: 61))
        #expect(!model.isSystemShortcut)
    }

    @Test("recording is unavailable while a dictation runs")
    func unavailableWhileDictating() {
        // Pausing River's shortcuts mid-dictation would take away the key that stops it.
        let log = HooksLog()
        log.pauseAllowed = false
        let model = ShortcutRecorderModel(hooks: log.hooks)
        model.start()
        #expect(model.phase == .idle)
    }
}

@MainActor
private final class HooksLog {
    var pauses = 0
    var resumes = 0
    var saved: [Shortcut] = []
    var registration: HotKeyRegistration = .registered
    var system: [SystemShortcuts.Entry] = []
    var pauseAllowed = true

    var hooks: ShortcutRecorderHooks {
        ShortcutRecorderHooks(
            pause: { self.pauses += 1; return self.pauseAllowed },
            resume: { self.resumes += 1 },
            probe: { _ in self.registration },
            save: { self.saved.append($0) },
            systemShortcuts: { self.system }
        )
    }
}
