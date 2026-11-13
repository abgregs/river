# Architecture: AppState and the menu bar

How the UI observes the dictation cycle without the cycle knowing the UI exists.

[`RiverSession`](river-session.md) is deliberately UI-agnostic — it imports no SwiftUI and exposes Combine publishers (`state`, `errors`, `notices`). `AppState` is the thin bridge that turns those publishers into something SwiftUI can observe; the menu bar reads `AppState`. **Why:** the session stays a pure cycle owner and the test surface, while the UI stays a pure function of observed state. Neither reaches into the other.

## AppState — the Combine → `@Observable` bridge

`AppState` is `@MainActor @Observable` and holds exactly what the UI renders:

```swift
@MainActor @Observable
final class AppState {
    private(set) var state: RiverState = .idle
    private(set) var errorMessage: String?
    private(set) var notice: String?
    func bind(to session: RiverSession)   // sinks session.state + session.errors + session.notices
}
```

`AppDelegate` constructs one `AppState`, calls `bind(to: session)` once at launch, and hands it to the `MenuBarExtra`. The `cancellables` set is `@ObservationIgnored` so subscription bookkeeping doesn't trip observation.

Three rules live in the update entry points (all `internal` for testability — see [../conventions/tests.md](../conventions/tests.md)):

- **`apply(_ state:)`** — a fresh `.recording` clears `errorMessage`; leaving `.recording` clears `notice`, so a recording-context message never outlives the recording it described.
- **`apply(_ error:)`** — the **single choke point** where a `RiverError` becomes display text. It runs `LogRedaction.redactUserPaths(_:)` exactly once here, so a `/Users/<name>` path in a framework error can't ride onto the menu (and into a screenshot). This is the UI half of [ADR 0002](../decisions/0002-log-redaction-over-debug-flag.md); the log half redacts at the log sites.
- **`apply(notice:)`** — sets `notice` from a `session.notices` message (a live activation-settings change applied during a tap-mode recording). A recording-context heads-up, separate from `errorMessage`, with the clear-on-end lifecycle above.

## RiverError — the cycle-failure surface

`RiverSession` exposes `var errors: AnyPublisher<RiverError, Never>`. `RiverError` has one case per cycle stage (`.audioCapture` / `.transcription` / `.textInsertion`, each wrapping the underlying error). `handleDeactivate` emits the matching case from each stage's `catch` **without disturbing the return to `.idle`** — the error is a side signal, not a control-flow change (the cycle still always lands back at `.idle`; see [river-pipeline.md](river-pipeline.md)).

## MenuBarPresentation — pure state → visuals

The icon/label contract is a pure function, extracted from the view so it's unit-tested without standing up SwiftUI:

```swift
enum MenuBarPresentation {
    enum Glyph: CaseIterable { case ready, listening, transcribing; var assetName: String }
    enum Icon: Equatable { case glyph(Glyph); case symbol(String) }
    struct Visual: Equatable { let icon: Icon; let statusLabel: String }
    static func visual(state: RiverState, hasError: Bool, modelLoadState: ModelLoadState) -> Visual
}
```

Mapping (per [../requirements/core-feature.md](../requirements/core-feature.md) item 5):

| State | Icon | Label |
|---|---|---|
| `.idle` | 川 (`MenuBarReady`, template) | Ready |
| `.recording` | 川 with the red recording dot (`MenuBarWithDot`, the dot drawn by River) | Recording... |
| `.processing` | 川 with the dot in muted ink (`MenuBarWithDot`, the dot drawn by River) | Processing... |

The cycle states draw River's own mark: Ready is 川 (`MenuBarReady`, [../design/kawa-identity.md](../design/kawa-identity.md), replacing the stones r since 2026-11-02), Listening adds the red recording dot, and Transcribing turns it to muted ink (2026-11-04). The PNGs are template images the system tints. **Why:** the menu bar takes its look from the wallpaper, not from Light or Dark mode, so only a template image follows it; a colored image per mode measured about 1.5:1 on a tinted bar (on device, 2026-10-15; [../design/color.md](../design/color.md)). A template image cannot carry the red, so Listening and Transcribing are drawn when the bar draws them (`MenuBarGlyphImages.withDot`): the mark in the bar's text color and the dot in the red for the bar's own appearance, or in the text color at `menuBarMutedDotOpacity`, so both still follow the wallpaper. Every other state keeps an SF Symbol — `exclamationmark.triangle` for an error or a failed load, `arrow.down.circle` while downloading, `ellipsis` while loading. **Why:** the cycle states are the identity's glyph set, so they are assets, not symbols; the exceptional states are system vocabulary and stay system-drawn.

A pending error overrides **only the `.idle` icon** with `exclamationmark.triangle`; an active state's icon always wins (errors surface at end-of-cycle, so a live `.recording`/`.processing` glyph is never masked by a stale error). The label always reflects the raw state.

`RiverApp`'s `MenuBarExtra` label and content both render from `MenuBarPresentation.visual(state:hasError:modelLoadState:)` — the label switching on `Icon` to draw either a glyph image (`MenuBarGlyphImages`: the template PNG, or the PNG with its dot drawn over it) or an SF Symbol — with the error message and any recording-context `notice` shown as extra menu lines when present.

The menu holds the status line (with an error or notice when there is one), "Cancel Recording" (only while recording), "Copy Last Transcription", "Check for Updates…" (release builds only), "Settings…" and "Quit River" ([../planning/0036_settings-and-shortcuts.md](../planning/0036_settings-and-shortcuts.md)). "Settings…" calls `SettingsWindowController.show()`: one native window, kept for the session, whose Permissions section replaced the "Permissions…" item. Its rows bind to `@AppStorage(Settings.x.name)`; the Shortcuts section records through `ShortcutRecorderHooks`, which reach the session's `pauseShortcuts`, `resumeShortcuts` and `availability(of:)` and save through `SettingsStore`, and reads `AppState.dictationRegistration` for a shortcut that failed to register; the Model section reads `AppState.modelSelection` (the model in use, its load state, and the model loading beside it, from `TranscriptionManager.selection`) and chooses through `RiverSession.selectModel(_:)`.

## The seam is reusable

`AppState` is the shared observation seam: the recording indicator ([../planning/0002_recording-indicator-hud.md](../planning/0002_recording-indicator-hud.md), rebuilt as the river indicator in [0028](../planning/0028_identity-implementation.md)) is just another observer of the same `state`, `toast`, `notice`, `inputLevel`, `isAudioFlowing`, `modelLoadState`, and `liveTranscript` — not a new path into the session. `isAudioFlowing` turns true on the first level reading of a recording and false in any other state; the mark starts its voice layer on it, so a dead microphone never looks live ([../design/kawa-identity.md](../design/kawa-identity.md)). The mark, its messages, and the streaming transcript render as one bottom-anchored stack in one window ([../decisions/0003-floating-ui-one-window-stack.md](../decisions/0003-floating-ui-one-window-stack.md)).

A notice belongs to the recording it describes. `apply(_:)` clears it both when a recording **starts** and when one ends. **Why:** `handleCancel` sends `.idle` and *then* the cancel notice, so clearing only on the way out cannot catch it, and the message rode into the next recording (planning [0017](../planning/0017_cancel-recording.md)'s canceled-notice bleed, seen on device 2026-09-17).

`lastRecordingWasCanceled` records how the most recent recording ended. `apply(_:)` sets it as the state leaves `.recording`: only a cancel goes straight to `.idle`, and a stop always passes through `.processing`. **Why:** an observer of `state` runs once per turn, not once per change. An all-silence recording leaves `.processing` in the same turn it enters it (planning [0023](../planning/0023_silence-decoding-hardening.md)), so the sound cues ([0016](../planning/0016_recording-sound-cues.md)) see `.recording → .idle` for both a cancel and a silent stop. They read this flag to choose the cancel cue or the end cue.

## Related

- [river-session.md](river-session.md) — the UI-agnostic cycle owner whose `state`/`errors` publishers this bridges
- [river-pipeline.md](river-pipeline.md) — where `RiverError` is emitted per stage
- [../decisions/0002-log-redaction-over-debug-flag.md](../decisions/0002-log-redaction-over-debug-flag.md) — why the error message is path-redacted at this boundary
- [../decisions/0003-floating-ui-one-window-stack.md](../decisions/0003-floating-ui-one-window-stack.md) — why the floating surfaces share one window and one stack
- [../requirements/core-feature.md](../requirements/core-feature.md) — item 5, the visible-feedback requirement this satisfies
- [../conventions/tests.md](../conventions/tests.md) — the `apply` / `visual` test seams
