# Design direction: River

The identity brief for the design phase that follows the naming decision ([../planning/0027_project-naming.md](../planning/0027_project-naming.md)). It fixes the *direction* — what the app should feel like and why — so that the icon, motion, sound, and page work that follows makes decisions against the same idea. It is not a spec; each surface below gets its own numbered planning item when it is picked up.

## The idea

**Text flows in and follows you.** You speak; words arrive at the cursor in whatever app you are in. The name is the metaphor: a river is continuous, goes wherever the ground goes, and is calm at the surface while moving underneath. The 0025 streaming-dictation direction (continuous insertion instead of paste-at-the-end) makes this literal later; the identity should anticipate it now.

**How it should feel:** sharp, snappy, responsive. Motion is *subtle yet striking* — fluid, never bouncy — and appears only where it carries meaning. The app is a utility that lives in the menu bar; it should be invisible until you call it and unmistakable while it is working.

## Principles

1. **Motion is state, never decoration.** Every animation maps to a transition on the cycle state seam ([../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md)): `.idle → .recording → .processing → .idle`, plus `.loading` and errors. If a transition has no motion, that is a decision; if a motion has no transition, it goes.
2. **Never steal focus.** The HUD is a non-activating panel that must not become key ([../planning/0002_recording-indicator-hud.md](../planning/0002_recording-indicator-hud.md)). No surface may pull the caret away from where the text is about to land. Identity work lives inside that constraint, not around it.
3. **Fluid, not bouncy.** Continuous easing curves and crossfades over springs and overshoot. The water vocabulary is *current, ripple, flow* — restrained, low amplitude, short. A recording is not a splash.
4. **Platform first.** SF Symbols and system materials by default; light and dark appearance; Reduce Motion honored (motion degrades to a crossfade, never to nothing); no custom fonts. Custom assets earn their place per surface, below.
5. **Quiet by default.** No sound unless opted in (the 0016 toggle), no persistent panels, no nagging. The HUD fades out on `.idle`; errors are transient toasts, not pinned warnings (0018). Cutting an animation is always an acceptable outcome of a review.

## Surfaces

| Surface | Today | Direction |
|---|---|---|
| **App icon** | **Shipped 2026-09-17** ([0028](../planning/0028_identity-implementation.md)): `River.icns`, the five-slat mark in ink on a charcoal squircle, rendered from the same geometry as the menu bar glyph. | The accent is deliberately *not* on it yet — ink and charcoal keep it consistent with every other River mark. A fuller pass (accent, a mark beyond the slats) stays open. |
| **Menu bar glyphs** | **Shipped 2026-09-17** ([0028](../planning/0028_identity-implementation.md)): River's five-slat template images for the three cycle states; the warning, downloading, and loading states keep their SF Symbols. | Settled. The glyph is an 18 pt template asset, pixel-snapped per scale, generated from `Constants`. |
| **Recording HUD** | **Shipped 2026-09-17** ([0028](../planning/0028_identity-implementation.md)): `RiverIndicatorView` — three strands in a charcoal capsule, driven by the live input level, with the ink crest while transcribing; toasts (0018) and the loading label (0004) in their own rectangle below. The 0017 canceled-notice bleed is fixed. | Remaining: the insert moment once streaming exists (0025), the sub-second gate gap at `.loading → .ready`, and the lingering menu-bar warning after a gate-declined activation. |
| **Sound cues** | System sounds behind `playFeedbackSounds` (0016), **off by default** per principle 5, with a distinct cancel cue (0017). | Three short custom cues (start, stop, cancel) that share one timbre — crisp, not watery; under 200 ms; identical loudness. Move the sound names into `Constants` when replacing them (open follow-up on PR #31). |
| **Onboarding and Settings** | Functional SwiftUI windows; onboarding is the permissions walkthrough. | Copy and rhythm pass, the icon in the onboarding header, and the 0004 loading-copy refinement ("Preparing model…" instead of "Loading…"). No new chrome. |
| **README / GitHub page** | Text README with two screenshots. | **Deferred until the in-app identity exists.** Then: color, the icon, a short looping capture of the HUD, and the install command above the fold. Do not design the page before the app. |
| **DMG background** | Plain. | The icon and an arrow. Last. |

## Constraints to respect

- The three architecture seams stay put: identity work is additional observers of `AppState`, never new callers into `RiverSession` ([../architecture/river-session.md](../architecture/river-session.md)).
- Every timing that matters (fade durations, cue lengths) lives in `Constants`, not inline, per `AGENTS.md` rule 5.
- No new dependencies for animation or audio without a decision record in [../decisions/](../decisions/_index.md); SwiftUI and AVFoundation cover the surfaces above.
- Nothing here changes the bundle ID, the feed URL, or the cask — those are fixed by [0027](../planning/0027_project-naming.md).

## Open decisions

Settle these in the phase and record the answer here or in the surface's planning item.

- **Motion implementation:** settled 2026-09-17 — SwiftUI throughout. The indicator is a `TimelineView(.animation)` over a `Canvas`, with every number in a pure, unit-tested `RiverIndicatorPresentation`; no Core Animation, no `Timer`, no frame `Task`.
- **Accent color:** settled 2026-09-16: charcoal plus vivid turquoise (OKLCH hue 196), `#148284` on light and `#31C8CA` on dark grounds; pressed controls take white text on the light value and charcoal text on the dark one. See [identity-studies.md](identity-studies.md).
- **Glyphs:** a custom template family. The microphone slat glyph is accepted as the working menu bar glyph; see [identity-studies.md](identity-studies.md).
- **Cues:** custom recordings, or synthesized in code for zero asset weight?
- **Streaming preview:** should the HUD hint at continuous insertion before 0025 ships, or stay honest about paste-at-the-end?

## Sequence

After the first River build has been smoked on-device: ~~icon and menu bar glyphs → HUD motion pass~~ (both landed 2026-09-17 in [0028](../planning/0028_identity-implementation.md), together with the accent tokens) → sound cues → onboarding and Settings pass → README/page → DMG background. Each step is one planning item (`0028` onward) and one PR; none of them blocks a release. Still deferred from the HUD pass: the sub-second gate gap at `.loading → .ready` and the lingering menu-bar warning after a gate-declined activation.

## Related

- [../planning/0027_project-naming.md](../planning/0027_project-naming.md) — why the name, and the identifiers the design must not touch
- [../planning/0002_recording-indicator-hud.md](../planning/0002_recording-indicator-hud.md), [0018](../planning/0018_transient-error-toasts.md), [0020](../planning/0020_mic-level-meter.md) — the HUD, its toasts, and its meter
- [../planning/0016_recording-sound-cues.md](../planning/0016_recording-sound-cues.md) — the cue toggle and the current sounds
- [../planning/0004_model-loading-indicator.md](../planning/0004_model-loading-indicator.md) — the loading-copy refinement
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the seam every surface observes
