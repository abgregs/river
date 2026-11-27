# Architecture: RiverSession

`RiverSession` is the deep module that owns one full dictation cycle from activation to text-pasted. It is the single integration point for the four capability-gated managers (hotkey, capture, transcribe, insert), and the only place the `RiverState` machine is observed and mutated.

`AppDelegate` constructs a `RiverSession` at launch and calls `start()`. After that, the delegate is a thin lifecycle shell — it does not touch managers directly and does not own state. **Why:** keeping the integration in one module makes the cycle the unit of test, makes cross-cutting concerns (deferred reconfiguration, state transitions, error recovery) structural rather than scattered, and prevents the class of bug where AppDelegate accumulates orchestration logic over time.

## Interface

```swift
@MainActor
final class RiverSession {
    var state: AnyPublisher<RiverState, Never> { get }            // observable for UI
    var currentState: RiverState { get }                          // sync accessor for tests
    var errors: AnyPublisher<RiverError, Never> { get }           // per-stage cycle failures
    var notices: AnyPublisher<String, Never> { get }              // recording-context notices
    var liveTranscript: AnyPublisher<String, Never> { get }       // streaming text for the panel
    var isLiveTextShown: AnyPublisher<Bool, Never> { get }        // whether the panel shows it
    var dictationEvents: AnyPublisher<DictationEvent, Never> { get }  // a wait, a kept recording, held text
    var keptRecordingCount: AnyPublisher<Int, Never> { get }      // recordings a failed load kept

    func start() async throws        // begin listening; idempotent
    func stop() async                // tear down cleanly; idempotent
    func cancelWaiting()             // throw away a dictation waiting for the model
}
```

That's it. There is no `reconfigure(...)` method. The `errors` publisher emits a `RiverError` (one case per cycle stage) when capture, transcription, or paste fails — a side signal that never changes the cycle's return to `.idle`. The `notices` publisher emits a short message when a settings change is applied **live** during a tap-mode recording (e.g. "the new key now stops the recording"). The UI observes these publishers through [`AppState`](app-state-and-menu-bar.md), not directly. **Why:** configuration changes flow in via subscription to [SettingsStore](settings-store.md) publishers inside the session — pushing configuration into the session externally would re-create the leak we're trying to remove.

## What the session owns

1. **The `RiverState` machine** (`.idle` / `.recording` / `.processing`). The session is the only writer; the menu bar and content views observe via the `state` publisher.
2. **The cycle orchestration.** When the hotkey fires `onActivate`, the session transitions to `.recording`, makes the recording's `DictationStream` and starts the capture that feeds it, whatever the model is doing. When `onDeactivate` fires, it transitions to `.processing`, stops capture, has the stream finish, waiting for a model not yet ready when the stream asks (item 8), types the text, and returns to `.idle`. Each stage's failure is caught independently and emitted as a `RiverError` on the `errors` publisher, without blocking the return to `.idle`.
3. **Live-or-deferred reconfiguration.** When an activation key/mode change arrives via a SettingsStore publisher, the session applies it by state and active mode: immediately when idle; **live, in place** during a tap-mode recording (plus a `notices` emission); deferred to the next `.idle` during a Hold recording or `.processing`. The session tracks the `activeMode` driving the current recording to make that choice. This is internal — callers never see it.
4. **Re-entrancy guards.** Activations during `.recording` or `.processing` are no-ops with logging. Out-of-order events are no-ops with logging.
5. **Microphone readiness.** The session combines the `keepMicrophoneReady` setting, whether onboarding is complete (the three capabilities' statuses through `OnboardingGate`) and the system's availability, puts them through the pure `MicrophoneReadiness` rule, and tells `AudioCaptureManager` whether to keep the capture unit running between recordings ([river-pipeline.md](river-pipeline.md), "The ready microphone and the pre-roll"). This is not the apply-or-defer path in item 3: the manager owns the unit and applies a mid-recording change itself when the recording ends.
6. **The last transcript, outside the cycle.** `pasteLastTranscript()` types it again through the delivery, after any insert still typing, in every state but one: a tap-mode dictation still recording, or one being transcribed, doesn't block it, and that dictation's text takes its turn after it. While a Hold dictation records it does nothing, and a Hold dictation that starts while it waits or types stops it, since its keys would land under the held dictation key; with a lone-modifier key held, `HotkeyManager` ends that recording before the press reaches the session, so the paste then types ([0036](../planning/0036_settings-and-shortcuts.md)). A change of app while it types stops it too. Neither shows anything, and a failure goes out as a `.textInsertion` error. `copyLastTranscript(to:)` copies it for the menu item and the Copy last shortcut ([0036](../planning/0036_settings-and-shortcuts.md)); it stays in the session, outside `TextInsertionManager`, so the typing path never holds clipboard code ([0011](../planning/0011_keystroke-injection.md), [0019](../planning/0019_last-transcript-recovery.md)). Neither changes the state.
7. **The live text's visibility.** `toggleLiveText()`, from its shortcut, flips `Settings.showLiveText`, during a recording or between recordings, and never touches the cycle. The session hands the setting to the recording's `DictationStream` as `showsPreview`, so a hidden live text runs no preview decodes ([0034](../planning/0034_live-text-and-microphone-settings.md)). A dictation that starts before the model is ready never shows it: it would sit empty through the wait and take the mouse.
8. **Dictating before the model is ready** ([0004](../planning/0004_model-loading-indicator.md)). A dictation that ends while the model downloads or gets ready waits in `.processing`, so a press meanwhile is ignored, on `TranscriptionManager.waitUntilReady()`, then decodes as usual; its live-text segments fail until then, and the stream decodes from the first of them in one piece. The stream asks for the wait just before that decode, and only for a clip that holds speech, so a stray tap never waits. The session sends `dictationEvents` before `.idle`: `.waitingForModel`, then `.recordingKept` if the load fails, or `.textHeld` if the app in front at the release leaves the front before or while River types, when the delivery stops and the session holds the text as the last transcript. A failed load keeps that clip in memory; the next load that succeeds transcribes the kept recordings at `.idle`, one at a time, each through `DictationStream` as its dictation would have been, joins them with a space and holds the text, never typed. `TranscriptionManager` decodes one clip at a time, in the order asked, so a kept recording's decode never runs beside a dictation's, a decode that Cancel or Discard left running included ([0039](../planning/0039_pipeline-rule-owners.md)). `cancelWaiting()`, the menu's Cancel Dictation, throws a waiting dictation away; the model keeps loading.

## What the session does not own

- The CGEventTap thread. That's owned by [`InputMonitoringCapability`](capabilities.md), which `HotkeyManager` builds on.
- Model loading. That's owned by `TranscriptionManager` and happens on its own schedule; the session only waits on its published state.
- What audio each decode gets. That's owned by the recording's `DictationStream`: the silence trim, the cuts, the overlap, the joins and the one-piece decode, for every path ([0039](../planning/0039_pipeline-rule-owners.md)). The session hands it the recording and gets text back.
- Settings storage. That's owned by [`SettingsStore`](settings-store.md). The session subscribes; it does not persist.
- UI. The session imports no SwiftUI. The menu bar observes `state` and `errors` through the [`AppState`](app-state-and-menu-bar.md) bridge; the session never reaches into the UI.

## How it composes

```
              ┌─────────────────────────────────┐
              │       RiverSession          │
              │  ┌─────────────────────────┐    │
              │  │  RiverState machine │    │
              │  └─────────────────────────┘    │
              │  ┌─────────────────────────┐    │
              │  │  pending reconfiguration│    │
              │  └─────────────────────────┘    │
              └──┬──────────┬──────────┬────────┘
                 │          │          │
                 ▼          ▼          ▼
           HotkeyManager  AudioCapture  TextInsertion
                 │             │             │
                 ▼             ▼             ▼
        InputMonitoring   Microphone    Accessibility
           Capability     Capability     Capability
```

`RiverSession` consumes the managers; the managers consume capabilities. No call ever skips a layer. The session also reads `SystemAvailabilityMonitor` (sleep, lock and session state) as one input to microphone readiness; the monitor gates no OS call, so it sits outside this layering.

## Reconfiguration without leaks

When the user changes the dictation shortcut or mode in Settings:

1. SwiftUI writes through to `UserDefaults` via `@AppStorage`.
2. `SettingsStore.publisher(for: .dictationShortcut)` (or `.activationMode`) emits the new typed value.
3. The session's subscription receives it and branches on `currentState` + `activeMode`:
   - **`.idle`** → `HotkeyManager` reconfigures the hotkey **in place** (swap the watched key/mode; the one event tap keeps running — no rebuild, see [threading-invariant.md](threading-invariant.md)).
   - **`.recording` in a tap mode** → applied **live, in place**; the recording keeps running and the session emits a `notices` message so the user knows the new key/mode now stops it. The surviving tap is why no audio is dropped — this is *not* the mid-cycle teardown anti-pattern #7 forbids; the session owns the change and there is no `tapCreate`.
   - **`.recording` in Hold mode, or `.processing`** → stored as a pending reconfiguration and applied on the next return to `.idle`. Hold defers because the held old key's release must still stop the recording.

**Why this matters:** in the previous-generation design, `AppDelegate` had to filter `UserDefaults.didChangeNotification`, compare to last-applied values, and orchestrate the deferral. All of that is gone — typed publishers, an in-place swap with no tap teardown, and a structural live-or-defer choice inside the session.

## Testability

The session is the test surface for the cycle. Tests construct a `RiverSession` with stubbed managers (replaced with fakes as each manager gains real behavior in M4–M7) and a `SettingsStore` backed by a per-test `UserDefaults` suite, then drive it with synthetic activations and observe the state publisher:

```swift
@Test("activation during processing is ignored")
func activationDuringProcessingIsIgnored() async throws {
    let fakeHotkey = FakeHotkey()
    let session = RiverSession(/* fakes injected */)
    try await session.start()

    fakeHotkey.fireActivate()
    fakeHotkey.fireDeactivate()
    // now in .processing
    fakeHotkey.fireActivate()  // should be no-op
    #expect(session.currentState == .processing)
}
```

Configuration-subscription wiring is asserted indirectly through internal counters (`configurationApplyCount`, `configurationDeferCount`) — see [../conventions/test-seams.md](../conventions/test-seams.md) — so tests confirm the apply-or-defer branch without inspecting handler closures.

`handleActivate` is sync (state changes immediately; audio start is fire-and-forget). `handleDeactivate` is async — tests `await` it directly to drive the full `.recording → .processing → .idle` cycle within the test's own timeline rather than waiting on the Task the production callback wraps it in. `pasteLastTranscript` is async for the same reason.

End-to-end tests with real capabilities are integration tests run manually before release; the session's unit tests cover the cycle logic itself.

## Related

- [overview.md](overview.md) — where the session sits in the process model
- [capabilities.md](capabilities.md) — the capability layer the session's managers depend on
- [settings-store.md](settings-store.md) — the typed publishers the session subscribes to
- [river-pipeline.md](river-pipeline.md) — the step-by-step cycle the session implements
- [../conventions/tests.md](../conventions/tests.md) — testing patterns for the session
