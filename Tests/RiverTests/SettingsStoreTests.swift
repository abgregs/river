import Combine
import Foundation
import Testing
@testable import River

@Suite("SettingsStore")
struct SettingsStoreTests {
    @MainActor
    @Test("round-trips activationKeyCode with default")
    func roundTripsWithDefault() async throws {
        let store = makeStore()
        #expect(store.value(for: Settings.activationKeyCode) == Settings.activationKeyCode.defaultValue)
        store.setValue(42, for: Settings.activationKeyCode)
        #expect(store.value(for: Settings.activationKeyCode) == 42)
    }

    @MainActor
    @Test("publisher emits only when value changes")
    func publisherDedupes() async throws {
        let store = makeStore()
        var received: [Int] = []
        let token = store.publisher(for: Settings.activationKeyCode).sink { received.append($0) }
        defer { token.cancel() }

        store.setValue(7, for: Settings.activationKeyCode)
        store.setValue(7, for: Settings.activationKeyCode)
        store.setValue(9, for: Settings.activationKeyCode)

        #expect(received == [Settings.activationKeyCode.defaultValue, 7, 9])
    }

    @MainActor
    @Test("round-trips [String] and Bool settings")
    func roundTripsCollectionAndBool() async throws {
        let store = makeStore()
        #expect(store.value(for: Settings.customDictionaryTerms) == [])
        store.setValue(["Swift", "WhisperKit"], for: Settings.customDictionaryTerms)
        #expect(store.value(for: Settings.customDictionaryTerms) == ["Swift", "WhisperKit"])

        #expect(store.value(for: Settings.launchAtLogin) == false)
        store.setValue(true, for: Settings.launchAtLogin)
        #expect(store.value(for: Settings.launchAtLogin) == true)
    }

    // A shipping default the user meets before they open Settings: "quiet by default"
    // (design/direction.md principle 5) means a fresh install makes no sound.
    @Test("feedback sounds are off until the user opts in")
    func feedbackSoundsDefaultOff() {
        #expect(Settings.playFeedbackSounds.defaultValue == false)
    }

    // The ready microphone is the default (planning 0033, decision 3): the switch exists
    // to turn it off, so an off default would silently reintroduce the clipped first word.
    @MainActor
    @Test("the microphone stays ready unless the user opts out, and the switch round-trips")
    func keepMicrophoneReadyDefaultsOnAndRoundTrips() {
        let store = makeStore()
        #expect(Settings.keepMicrophoneReady.defaultValue == true)
        #expect(store.value(for: Settings.keepMicrophoneReady) == true)
        store.setValue(false, for: Settings.keepMicrophoneReady)
        #expect(store.value(for: Settings.keepMicrophoneReady) == false)
    }

    @MainActor
    @Test("round-trips selectedModel with default")
    func roundTripsSelectedModel() async throws {
        let store = makeStore()
        #expect(store.value(for: Settings.selectedModel) == Constants.defaultModel)
        store.setValue("openai_whisper-base.en", for: Settings.selectedModel)
        #expect(store.value(for: Settings.selectedModel) == "openai_whisper-base.en")
    }

    @MainActor
    @Test("selectedModel publisher emits only when the value changes")
    func selectedModelPublisherDedupes() async throws {
        let store = makeStore()
        var received: [String] = []
        let token = store.publisher(for: Settings.selectedModel).sink { received.append($0) }
        defer { token.cancel() }

        store.setValue("openai_whisper-base.en", for: Settings.selectedModel)
        store.setValue("openai_whisper-base.en", for: Settings.selectedModel)  // no-op
        store.setValue("distil-whisper_distil-large-v3", for: Settings.selectedModel)

        #expect(received == [Constants.defaultModel, "openai_whisper-base.en", "distil-whisper_distil-large-v3"])
    }

    @MainActor
    @Test("round-trips a RawRepresentable enum (ActivationMode) as its raw value")
    func roundTripsActivationMode() async throws {
        let store = makeStore()
        #expect(store.value(for: Settings.activationMode) == .hold)  // default
        store.setValue(ActivationMode.doubleTap, for: Settings.activationMode)
        #expect(store.value(for: Settings.activationMode) == .doubleTap)
    }

    @MainActor
    @Test("activationMode publisher dedupes; an @AppStorage-style raw write reaches it as the enum")
    func activationModePublisher() async throws {
        // SwiftUI's @AppStorage writes the *raw string* straight to UserDefaults.
        // The store must decode it back to ActivationMode and emit it, or the
        // session never hears a mode change from the UI (the M8 bridge bug class).
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        var received: [ActivationMode] = []
        let token = store.publisher(for: Settings.activationMode).sink { received.append($0) }
        defer { token.cancel() }

        store.setValue(ActivationMode.singleTap, for: Settings.activationMode)
        store.setValue(ActivationMode.singleTap, for: Settings.activationMode)  // no-op
        defaults.set(ActivationMode.doubleTap.rawValue, forKey: Settings.activationMode.name)  // bypasses setValue
        await waitUntil { received.last == .doubleTap }

        #expect(received == [.hold, .singleTap, .doubleTap])
    }

    @MainActor
    @Test("an external UserDefaults write (like @AppStorage) reaches the publisher")
    func externalWriteReachesPublisher() async throws {
        // The load-bearing M8 path: SwiftUI `@AppStorage` writes straight to
        // UserDefaults, bypassing `setValue`. If the store doesn't bridge that into
        // its publisher, `RiverSession` never hears a settings change from the UI
        // and live-apply silently breaks — the exact gap this regression guards.
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        var received: [Int] = []
        let token = store.publisher(for: Settings.activationKeyCode).sink { received.append($0) }
        defer { token.cancel() }

        defaults.set(99, forKey: Settings.activationKeyCode.name)   // bypasses setValue
        await waitUntil { received.last == 99 }
        #expect(received.last == 99)
    }

    @MainActor
    @Test("a stored value that is neither castable nor DefaultsConvertible falls back to the default")
    func undecodableStoredValueFallsBackToDefault() async throws {
        // Defensive: if some other process (or a schema change) leaves a value of
        // the wrong type under a key, `readValue` must return the typed default,
        // not trap. `activationKeyCode` is an `Int` (not `DefaultsConvertible`), so
        // a stored `String` is neither directly castable nor decodable — the
        // last-resort `return key.defaultValue` path.
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set("not an int", forKey: Settings.activationKeyCode.name)
        let store = SettingsStore(defaults: defaults)
        #expect(store.value(for: Settings.activationKeyCode) == Settings.activationKeyCode.defaultValue)
    }

    @MainActor
    private func makeStore() -> SettingsStore {
        let suite = "test-\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)   // up to ~1s total
        }
    }

    // MARK: - activationKeyCode migration (spec 0036)

    @MainActor
    @Test("a saved lone-modifier key becomes the dictation shortcut, and the old key is dropped")
    func migratesValidKey() {
        // A user upgrading to v0.3.0 keeps the key they chose. The old key is removed
        // so it can never be read again, or migrate a second time over a newer choice.
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        defaults.set(59, forKey: Settings.activationKeyCode.name)
        let store = SettingsStore(defaults: defaults)

        store.migrateActivationKeyCode()
        #expect(store.value(for: Settings.dictationShortcut) == .modifier(keyCode: 59))
        #expect(!store.hasStoredValue(for: Settings.activationKeyCode))
    }

    @MainActor
    @Test("a saved key that is no longer a dictation key is dropped and the default applies", arguments: [
        57 as Any,          // Caps Lock: removed, no mode works on it
        49 as Any,          // never a supported key
        "garbage" as Any,   // unreadable
    ])
    func dropsInvalidKey(_ saved: Any) {
        // Migrating it would hand the user a key that cannot work; the default does.
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        defaults.set(saved, forKey: Settings.activationKeyCode.name)
        let store = SettingsStore(defaults: defaults)

        store.migrateActivationKeyCode()
        #expect(!store.hasStoredValue(for: Settings.dictationShortcut))
        #expect(store.value(for: Settings.dictationShortcut) == .modifier(keyCode: 61))
        #expect(!store.hasStoredValue(for: Settings.activationKeyCode))
    }

    @MainActor
    @Test("the migration never overwrites a dictation shortcut already saved")
    func keepsExistingShortcut() {
        // "Once": a shortcut recorded after the upgrade wins over the leftover old key.
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let combination = Shortcut.combination(keyCode: 49, modifiers: [.control, .option])
        defaults.set(combination.rawValue, forKey: Settings.dictationShortcut.name)
        defaults.set(59, forKey: Settings.activationKeyCode.name)
        let store = SettingsStore(defaults: defaults)

        store.migrateActivationKeyCode()
        #expect(store.value(for: Settings.dictationShortcut) == combination)
        #expect(!store.hasStoredValue(for: Settings.activationKeyCode))
    }

    @MainActor
    @Test("with nothing saved the migration writes nothing")
    func noSavedKeyIsNoOp() {
        // A fresh install must keep reading the default, not a pinned copy of it, so
        // a future default change still reaches it.
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let store = SettingsStore(defaults: defaults)

        store.migrateActivationKeyCode()
        #expect(!store.hasStoredValue(for: Settings.dictationShortcut))
    }
}
