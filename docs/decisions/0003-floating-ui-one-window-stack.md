# ADR 0003: One window and one bottom-anchored stack for the floating UI

**Status:** Accepted — 2026-10-12. Amended 2026-11-21: the model's status row beside the mark.

## Context

River floats three surfaces above the Dock: the mark's panel (the recording state), a message rectangle (the error toast, the "Preparing model…" label, the mid-recording notice), and the streaming transcript (0025). Until this change they lived in two windows, each owned by its own coordinator:

- `RecordingIndicatorCoordinator` placed the mark and the message. The message sat at a hand-computed offset: above the mark while it showed, on the mark's baseline once it had faded.
- `TranscriptPanelCoordinator` placed the transcript at its own hand-computed offset, the mark's height plus the stack spacing above the Dock. It borrowed the indicator's constants to do so.

In web terms these were separate `position: fixed` elements with fixed `bottom` values. Neither knew the other's height. Three problems followed:

1. **Overlap.** The message and the transcript used the same position, so they covered each other when both showed. That happens when a transcription error arrives while the transcript still holds text (errors are sent during `.processing`), and when an activation-key change sends a notice mid-recording. A toast's height varies with its copy, so a fixed offset cannot reserve the right gap.
2. **Two places to change.** The transcript's position depended on constants in another file. Moving or resizing the mark meant keeping both coordinators in step.
3. **Two windows to keep on screen.** Planning [0030](../planning/0030_floating-ui-visibility.md) found that the window server can drop a long-lived panel from every Space. The fix had to be applied twice, once per coordinator.

## Decision

One window holds every floating surface. `RecordingIndicatorCoordinator` owns it; `TranscriptPanelCoordinator` is deleted. `RiverIndicatorView` lays the surfaces out as one SwiftUI `VStack`, bottom-aligned in a fixed frame: the transcript, then the message, then the mark, `hudStackSpacing` apart. The web analogue is a flex column with `justify-content: flex-end`.

Each surface is in the stack only while it shows, and enters and leaves with the shared fade. The surfaces above it close the gap, so:

- a taller toast pushes the transcript up instead of covering it;
- when the mark fades, a toast left behind drops into its place.

The window is sized for the tallest stack (`RiverIndicatorView.contentSize` plus the shadow margin) and never resizes. The window ignores the mouse, as the indicator always did, except while the transcript shows, when it takes the scroll wheel.

## Rationale

- **The layout follows the content.** Surfaces are positioned by what is actually on screen, not by offsets that assume what might be. Overlap cannot happen by construction, whatever a message's length.
- **One position to compute.** The coordinator anchors one window, centered just above the Dock; SwiftUI places everything inside it. A size change to any surface needs no change anywhere else.
- **One lifecycle.** One window to order in, fade out, and replace after it has been shown (0030), instead of two copies of that logic.
- **Room to grow.** Further floating surfaces, such as the action row planned after this, join the same stack instead of becoming a fourth separately positioned window.

## Consequences

- The window spans the whole stack (about 536 × 476 pt), far more than the 48 pt mark. Outside the transcript's lifetime it ignores the mouse, so it never blocks clicks. While the transcript shows, it relies on AppKit passing clicks on transparent pixels through to the app behind. The maintainer's on-device smoke test of this branch on 2026-10-12, which included clicking into the app above the Dock while dictating, found no problem.
- Every floating surface now shares one view and one coordinator, so a fault in either affects all of them.
- `TranscriptPanelView` is a plain view of the text. Its visibility rule (`isVisible(state:isShown:)` since planning 0034, which shows it for the whole dictation once the live text is on; `isVisible(state:text:)` before) stays on it, and both the stack and the coordinator's mouse decision read it.
- `AppState.apply(liveTranscript:)` lets tests show the transcript without a live session.

## Revisit if

- **A floating surface needs to sit outside the vertical stack**: anchored to the caret, beside the mark, or on another screen. One window would then have to grow far beyond its content, so give that surface its own window and record why.
- **Clicks stop passing through the window's transparent areas** while the transcript shows, for example after a macOS change. Then shrink the window's mouse region to the transcript, or move the transcript back to a window of its own.
- **The stack's fixed frame grows** past what fits above the Dock on small displays. Then cap the transcript's height, or let the window size follow its content.

## Amendment — 2026-11-21: the status row beside the mark

Planning [0004](../planning/0004_model-loading-indicator.md) puts the model's status in a one-line row 8 pt to the right of the mark's panel, once a dictation ends before the model is ready. That is the first case under **Revisit if**: a surface beside the mark, outside the vertical stack.

It stays in this window. The row hangs off the mark as an overlay, not as a member of the stack, and leaves on the mark's own clock: it fades and drops with the panel's exit, read from the same cycle's timeline. That clock is view state. One window shares it; a second window would have to copy it and keep the two exits in step, which is the coupling this decision removed.

The window widens so the widest row fits on either side of the centred mark: `RiverIndicatorView.contentSize` is at least 2 × (24 + 8 + `statusRowMaxWidth`) = 664 pt wide, 856 pt with the shadow margin, and a test measures every row River writes against it. The window still ignores the mouse outside the transcript's lifetime, so the row is never clickable and covers nothing it could take a click from.

The model-loading label above the mark is gone: nothing shows while the model loads at launch.

## Related

- [../planning/0002_recording-indicator-hud.md](../planning/0002_recording-indicator-hud.md) — the indicator's original window: non-activating, fixed position, never key.
- [../planning/0004_model-loading-indicator.md](../planning/0004_model-loading-indicator.md) — the status row the amendment places beside the mark.
- [../planning/0030_floating-ui-visibility.md](../planning/0030_floating-ui-visibility.md) — the panel-replacement fix this keeps, now in one coordinator.
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — `AppState`, the one seam the stack observes.
- [../design/color.md](../design/color.md) — the shared `HUDSurface` every surface in the stack uses.
