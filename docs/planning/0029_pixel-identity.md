# Planning: Pixel identity — the pixel r in the indicator, menu bar, and icon (roadmap 0029)

**Implemented 2026-09-24** on `feat/pixel-identity`. Replaces the marks 0028 shipped — the three-strand river indicator, the five-slat menu bar glyph, and the slat app icon — with one pixel-grid lowercase **r**, approved by the maintainer on 2026-09-24 after three rounds of prototypes. The accent tokens, the panel window, the toast rectangle, and every seam 0028 set up are unchanged. The reference implementation is [../design/studies/pixel-identity.html](../design/studies/pixel-identity.html): every number below was tuned there, and the rounds that led to it are recorded in [../design/pixel-identity.md](../design/pixel-identity.md).

## Problem

The UI-first phase ([current-focus.md](current-focus.md)) starts by settling the mark before anything is built around it. The 0028 marks were two unrelated drawings: slats in the menu bar and in the icon, strands in the panel. The maintainer asked for one cohesive mark built from rounded squares, integrating the turquoise accent, with the same states and features and no new behavior.

## Design

### The mark

A 6×6 grid; the r is 16 cells (a two-wide stem, a shoulder, a dropped tip). One map in `PixelMark` is drawn by every surface: the live panel, the three menu bar glyphs, and the app icon (identity-studies working rule 8). Cells are rounded squares whose corner is 16% of the cell at every size.

### The panel (replaces the river capsule)

- **Geometry.** 5 pt cells and 2 pt gaps make a 40 pt mark; every resting edge lands on a whole pixel at 1× and 2× (the page's 4.5 pt cells fall on half pixels at 1×). The panel keeps the capsule's 56 pt height and 8 pt vertical padding and adds 12 pt at the sides: 64×56, a continuous rounded rectangle with a 13 pt corner (a square mark in a capsule reads as an oval). Surface, shadow, hairline, fade, and the message rectangle below are 0028's, untouched.
- **Rest.** The r at full ink. The panel is hidden at idle, so the r is seen as the panel fades out after a cycle.
- **Listening.** All 16 pixels move together into a 4×4 meter centered in the panel (the grid's middle four columns and rows; the first build sat it on the baseline, which read as anchored to the bottom of the panel) in 0.26 s on a strong ease-out (`cubic-bezier(0.23, 1, 0.32, 1)`). Pixels pair with meter slots by the shortest total squared travel, so no two paths cross; moving together, no two come closer than half a cell. Staggered orders were measured and rejected: in stroke order pixels pass fully through each other for about 0.4 s.
- **The meter.** Each column is its own readout. It hears the level a little late (0, 30, 60, or 120 ms, in shuffled order), re-reads it on its own clock every 0.12–0.26 s, and picks a height within the range the loudness allows (0.25 to 1.25 of it, gains 0.85/1/1/0.85). It rises at 22/s and falls at 6/s. Lit cells fill fractionally at the top, from ink at 16% to the dark accent `#31C8CA` at 95%. Silence settles every column to a half-lit bottom row, so quiet listening never looks like rest. The meter reads loudness in decibels of full scale, from the capture trim's floor (`Constants.silenceTrimFloor`, about −50 dBFS since the quiet-speech trim fix in [0023](0023_silence-decoding-hardening.md)) to a ceiling of −28 dBFS (a full column), so quiet talking near −42 reaches a third of the range. The floor is shared on purpose: the meter never lights for a recording the trim then discards as silence (an earlier −58 floor would have shown whispers that were thrown away). The first build read `inputLevel` linearly, and quiet speech on the maintainer's built-in mic did not register at all (smoke, 2026-09-24). The mapping is display only: it reads `inputLevel`, which nothing on the capture path uses, and `MicrophoneCapability`'s 0.08 RMS reference is untouched. The page keeps its browser mapping, since a browser's gain control changes the levels (0028 item 4).
- **Transcribing.** The pixels return to the r in 0.24 s, then 0028's crest carries over: a raised-cosine window (half-width 0.32 of the stroke) of full ink runs the stroke from the stem's foot to the tip every 2.0 s over a 55% base, entering and leaving fully so the loop never pops. No accent.
- **State changes.** Every pixel's ink and tint follow their target at 18/s (about 0.17 s), and a travel retargets from where the pixel is, so interruptions never jump.
- **Reduce Motion.** No travel: the mark dips out and back over 0.24 s and the layout swaps at the bottom of the dip. The columns move together on the smoothed level (attack 10/s, release 5/s). Transcribing is the dithered r below.
- **Increase Contrast.** Every cell's ink has a 40% floor, so dim cells never drop out.
- **Preparing.** While the model gets ready at idle (the 0004 load window), the panel shows the r with the same raised-cosine crest, slower (3.0 s) and over a dimmer 40% base, so it reads as waiting rather than working on your words; Reduce Motion shows the dithered r. It replaces the spinner. The label below is text only, renamed "Preparing model…" (menu bar: "Preparing model..."), and when it is the only message its rectangle fits the text and centers under the mark.
- **Accessibility.** Unchanged: the panel speaks "Listening" or "Transcribing" and the elapsed time; the pixels are hidden. The states differ without color: the r, the meter's shape, and the r with ink moving through it.

### The menu bar glyphs

Static template images, one per state, swapped with no transition (the menu bar never animates; macOS already shows its own microphone indicator). 2.5 pt cells and 0.5 pt gaps (5 px and 1 px at 2×) in the 18 pt box: denser than the panel, because 1 pt gaps at this size read as dots. At 1× the cells are 2 px with 1 px gaps. The grid sits at the box's origin so every edge lands on a device pixel. **Ready:** the r. **Listening:** a frozen meter reading, bars 3·1·4·2, centered, with no unlit cells (dim cells read as a gray block; 2·3·4·1 reads as a signal-strength icon). **Transcribing:** the r with every other cell at 30% (removing them breaks the r apart; 45% is hard to tell from Ready). The menu bar carries no accent.

### The app icon

The r at rest, in ink on the charcoal squircle, at the panel's cell-to-gap proportion and 52% of the squircle's width, drawn by the same function as the menu bar glyphs. No accent, as in 0028.

### Code

- `PixelMark` — the map, the stroke order, the meter pairing, the dither, the static readings, and the cell layout.
- `PixelMarkPresentation` / `PixelMarkFrame` — the pure motion, advanced once per display frame like 0028's `RiverIndicatorFrame`. Randomness comes from a seedable generator carried in the frame, so tests and snapshots are repeatable.
- `PixelMarkRenderer` — the one drawing shared by the live `Canvas` and the snapshot harness.
- `RiverIndicatorPresentation`, the strand constants, and the slat glyph constants are deleted; the capsule sizes are renamed `indicatorPanel*`.

## Acceptance criteria

1. While `.recording`, the pixels drop into the meter and each column follows the live level out of step with the others; silence rests on the half-lit bottom row. Side by side with the study page at similar levels, the motion matches.
2. On `.processing` the pixels return to the r and the ink crest runs the stroke; on `.idle` the panel fades out as in 0028.
3. The toast, loading label, and notice appear as before, in their rectangle below the panel.
4. Reduce Motion: no pixel travels; transcribing is the dithered r; every state is distinguishable. Increase Contrast: no cell drops out. VoiceOver reads the state and the elapsed time.
5. The menu bar shows Ready, Listening, and Transcribing crisp at 1× and 2× on light and dark bars; the warning, downloading, and loading states are unchanged.
6. Finder and the Dock show the pixel r icon.
7. Unit tests pin the map, the pairing, the static readings, the pixel-exact geometry, and the motion (drop, interruption, silence, loudness, independence, Reduce Motion, transcribing). `swift build` and `swift test` pass; the asset drift checks pass after regeneration.
8. No new `CGEvent.post`, `AVAudioEngine.start`, or `CGEvent.tapCreate` call sites; `Info.plist` and entitlements untouched; the bundle passes `make verify`.
9. Manual smoke on device (the maintainer): light, dark, and near-black desktops; Reduce Motion and Increase Contrast; all three activation modes; a cancel; a toast; a 1× display if available. Check the meter against real speech (speech should lift the columns and silence should rest on the half-lit row; tune `pixelMeterCeilingDecibels`, and the floor only through the capture trim), and watch the meter for the "chaotic pillars" failure recorded in the studies ([../design/identity-studies.md](../design/identity-studies.md)).

## Related

- [../design/pixel-identity.md](../design/pixel-identity.md) — round ten: the decisions, the revisions to earlier confirmed rules, and the rejected attempts
- [../design/studies/pixel-identity.html](../design/studies/pixel-identity.html) — the reference implementation
- [0028_identity-implementation.md](0028_identity-implementation.md) — the build this replaces the marks of; its seams, surface, and harnesses carry over
- [../conventions/test-harnesses.md](../conventions/test-harnesses.md) — how the glyphs and icon are generated and checked
