# Design: Pixel identity (round ten, 2026-09-24)

The identity round that replaced the 0028 marks with one pixel-grid lowercase **r**: what the maintainer approved, which earlier confirmed rules it deliberately revises, every rejected attempt with its reason, and the working rules the round taught. [identity-studies.md](identity-studies.md) holds rounds one to nine; read both before proposing icon, glyph, indicator, or palette work. The reference implementation is [studies/pixel-identity.html](studies/pixel-identity.html) (serve the folder over localhost; the microphone needs a secure context). The native build is [../planning/0029_pixel-identity.md](../planning/0029_pixel-identity.md).

## Approved by the maintainer

- **One mark, built from rounded squares.** A 6×6 grid; the r is 16 cells. The menu bar glyphs, the recording indicator, and the app icon all draw it (working rule 8 of the studies). Requested as a design-only change: same states, same features, the turquoise accent integrated.
- **Drop & Play** (chosen 2026-09-24 over Lines and Caret below). The r at rest; while listening, all 16 pixels move into a 4×4 meter centered in the panel; while transcribing, they return to the r and an ink crest runs the stroke.
- **A square 4×4 meter**, proposed by the maintainer, replacing the first build's 3·3·3·3·2·2 columns: symmetric and centered under the r, 16 slots for 16 pixels, every column able to reach full height.
- **Independent columns.** Directed after the first look: each column is its own readout, rising and falling out of step with the others, "for a more eye-catching, dynamic effect". The mechanism (own clock, own delay, random reach within the loudness) keeps every column tied to the voice: silence settles all four.
- **A static menu bar.** Agreed 2026-09-24: one template icon per state, no animation (it would be tiny, monochrome, and a second moving indicator beside macOS's own microphone dot). Ready is the r; Listening a frozen meter reading, bars 3·1·4·2; Transcribing the r in a 50% dither.
- **Preparing replaces the spinner** (2026-09-25): at launch the HUD shows the r with a slow, dim ink crest and the label "Preparing model…", after the maintainer found "Loading" and the stock spinner confusing and off-brand.
- **The app icon is redrawn from the r**, and the native panel uses 5 pt cells with 2 pt gaps so the r is sharp at 1× (both decided 2026-09-24).

## Earlier rules this round deliberately revises

These were confirmed in [identity-studies.md](identity-studies.md). They are revised on purpose; do not restore them as regressions.

| Earlier rule | Now |
|---|---|
| "State changes by ink, never by the shape growing or shrinking"; "structure is the identity and must not change" | The r and the meter are different shapes. The bounding box and the panel never change size. |
| "Uniform ink on marks"; 0028: "the accent never touches the mark" | The lit meter is the dark accent `#31C8CA`. The resting r, the transcribing crest, the menu bar, and the icon stay ink. |
| "The app icon and any r-based glyph are dropped"; the slat glyph accepted as the menu bar mark | The pixel r is the mark on every surface. The dropped work was drawing letterforms from curves and fonts; a letter built on a pixel grid is a different method. |

Still in force: charcoal plus vivid turquoise, concentric radii, no word or timer in the panel, the near-opaque charcoal surface, Reduce Motion degrading to a crossfade, and state never carried by color alone (the r, the meter's shape, and the r with moving ink differ without it).

## Rejected, with reasons

| Attempt | Why it failed |
|---|---|
| Six concepts brainstormed, three prototyped: Drop & Play, **Waterline** (the r fills with turquoise from the bottom), **Current** (a brightness crest flowing along the r) | Waterline and Current were the same r with different motion; the maintainer wanted genuinely different compositions |
| **ASCII probe**: Drop & Play drawn with `#`, `+`, `·` characters | An aesthetic check only, never a candidate; discrete character swaps read as glitch |
| **Lines**: three lines of text that become three river strands | Replaced by the maintainer's choice of Drop & Play |
| **Caret**: an I-beam inside a mirrored waveform, blinking in silence | Replaced by the maintainer's choice of Drop & Play |
| First build's hard cuts: colors snapping on every state change, a Waterline drain that restarted on a timer, on/off level cutoffs | Read as glitches; replaced by a per-cell ink follow (about 0.17 s) and fractional fills |
| Reassembly staggered in stroke order | Measured: pixels pass fully through each other for about 0.4 s. Pixels now travel together and the crest carries the stroke order in ink |
| Meter columns following one level in lockstep | "All rising and falling together"; replaced by independent readouts |
| 3·3·3·3·2·2 meter columns | Lopsided, with a stepped right edge that looked like a mistake |
| Menu bar glyphs with 1 pt gaps | Read as dotted braille next to the clock; 0.5 pt gaps at 2× give the glyph weight |
| Dim unlit cells in the Listening glyph | A muddy gray block at menu bar size |
| Listening glyph 2·3·4·1 / 2·4·3·1 | A signal-strength icon / a small pyramid |
| Transcribing glyph with the dim cells removed, or at 45% | Removed, the r falls apart; at 45% it is hard to tell from Ready |
| The panel as a snug capsule around the square mark | An oval; a square mark takes a rounded square |

## Working rules this round taught

1. **Concepts means compositions.** Asked for N concepts, bring N different designs, not motion variants of one mark.
2. **Carry order with ink, not with delays.** Staggering moving elements that share a space sends them through each other; move them together and let light carry the sequence.
3. **Measure motion before judging it.** Column independence, overlap, and busyness were measured headlessly (correlation, spread, direction changes per second) before anyone watched it; stills still cannot judge motion (studies rule 5).
4. **The menu bar has its own optical size.** The same map needs denser cells, no dim fills, and whole-pixel edges at 18 pt; one map, a geometry per size.
5. **Tie decorative randomness to the signal.** Independent columns stay honest by drawing their randomness from within the range the loudness allows, so silence still settles everything.
