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
    enum Glyph: String, CaseIterable { case ready, listening, transcribing }   // asset names
    enum Icon: Equatable { case glyph(Glyph); case symbol(String) }
    struct Visual: Equatable { let icon: Icon; let statusLabel: String }
    static func visual(state: RiverState, hasError: Bool, modelLoadState: ModelLoadState) -> Visual
}
```

Mapping (per [../requirements/core-feature.md](../requirements/core-feature.md) item 5):

| State | Icon | Label |
|---|---|---|
| `.idle` | slat glyph, Ready | Ready |
| `.recording` | slat glyph, Listening | Recording... |
| `.processing` | slat glyph, Transcribing | Processing... |

The three cycle states draw River's own five-slat template images (planning [0028](../planning/0028_identity-implementation.md)); every other state keeps an SF Symbol — `exclamationmark.triangle` for an error or a failed load, `arrow.down.circle` while downloading, `ellipsis` while loading. **Why:** the cycle states are the identity's glyph set, so they are assets, not symbols; the exceptional states are system vocabulary and stay system-drawn.

A pending error overrides **only the `.idle` icon** with `exclamationmark.triangle`; an active state's icon always wins (errors surface at end-of-cycle, so a live `.recording`/`.processing` glyph is never masked by a stale error). The label always reflects the raw state.

`RiverApp`'s `MenuBarExtra` label and content both render from `MenuBarPresentation.visual(state:hasError:modelLoadState:)` — the label switching on `Icon` to draw either a template `NSImage` or an SF Symbol — with the error message and any recording-context `notice` shown as extra menu lines when present.

## The seam is reusable

`AppState` is the shared observation seam: the recording indicator ([../planning/0002_recording-indicator-hud.md](../planning/0002_recording-indicator-hud.md), rebuilt as the river indicator in [0028](../planning/0028_identity-implementation.md)) is just another observer of the same `state`, `toast`, `notice`, `inputLevel`, and `modelLoadState` — not a new path into the session.

A notice belongs to the recording it describes. `apply(_:)` clears it both when a recording **starts** and when one ends. **Why:** `handleCancel` sends `.idle` and *then* the cancel notice, so clearing only on the way out cannot catch it, and the message rode into the next recording (planning [0017](../planning/0017_cancel-recording.md)'s canceled-notice bleed, seen on device 2026-09-17).

## Related

- [river-session.md](river-session.md) — the UI-agnostic cycle owner whose `state`/`errors` publishers this bridges
- [river-pipeline.md](river-pipeline.md) — where `RiverError` is emitted per stage
- [../decisions/0002-log-redaction-over-debug-flag.md](../decisions/0002-log-redaction-over-debug-flag.md) — why the error message is path-redacted at this boundary
- [../requirements/core-feature.md](../requirements/core-feature.md) — item 5, the visible-feedback requirement this satisfies
- [../conventions/tests.md](../conventions/tests.md) — the `apply` / `visual` test seams
