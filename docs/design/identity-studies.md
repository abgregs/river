# Design: Identity studies (round nine, 2026-09-16)

The state of River's identity exploration after nine rounds of interactive studies: what the maintainer confirmed, what is still a candidate, what was rejected and why, and the working rules the rounds taught. Read this before proposing any icon, glyph, indicator, or palette work, so rejected directions are not re-proposed and settled choices are not reopened.

The studies themselves are [studies/river-identity-studies.html](studies/river-identity-studies.html), a self-contained page: open it in a browser. The published copy is the maintainer's private artifact "River Identity Studies". The brief they serve is [direction.md](direction.md); product truth is [../../PRODUCT.md](../../PRODUCT.md).

## Confirmed by the maintainer

- **Palette: charcoal plus dark turquoise.** Charcoal `#23262B`, raised charcoal `#2E3238`, ink `#ECEEF1`, accent dark turquoise `#1F7F86` on light grounds and `#3FA3AA` on dark grounds. Chosen 2026-09-16 over red sand after the side-by-side comparison with measured contrast: turquoise passes every text and control pairing; red sand fails on white at 3.90:1.
- **Uniform ink on marks.** No selective accent color on individual strokes, "for now".
- **Rounded corners with concentric radii.** Outer radius equals inner radius plus padding, per `better-ui`. The studies use a 16 pt panel radius, 12 pt padding, 4 pt inner radius.
- **Presence while recording: small but unmistakable.**
- **Untouched by this identity pass:** the menu bar dropdown, the Settings window layout, and the onboarding structure.
- **Anti-goals:** cute or mascot-like; the generic AI aesthetic (purple-blue gradients, sparkles, glowing orbs); heavy or decorative chrome. Literal water imagery was offered as an anti-goal and deliberately *not* chosen.
- **An indicator's empty and filled states are the same size.** State changes by ink, never by the shape growing or shrinking.
- **Menu bar glyph: the microphone slats.** Five horizontal slats, shortened toward the top and bottom, with distinct Ready, Listening, and Transcribing states. Accepted as is: "this works, keep it, no edits". Parked as the working glyph.
- **The recording indicator is that glyph, enlarged, at 48 pt.** Directed 2026-09-16: "a simple copying of the menu bar icon, just at a larger size". Its empty, initial state must match the menu bar's Ready glyph 1:1. Very subtle motion per stage (Ready, Listening, Transcribing) is welcome; the appearance is not to be redesigned.
- **The bar envelops the glyph.** Directed 2026-09-16, replacing the rounded-rectangle panel: two columns with a gap between them and the same padding in each; the left column holds the glyph, horizontally centered, the largest element and the one that sets the height; the right column holds only the time, horizontally centered. No "Listening" text anywhere. The bar's outline follows the glyph's contours with a consistent short gap, "perfectly enveloping" it, then wraps only the time, with none of the empty space of a wide rectangle. Width is fluid.
- **Bar construction: the group outline offset.** Chosen 2026-09-16 over the silhouette offset and the split shapes: the offset of the slat group's convex outline, one smooth contour, joined to the time capsule.
- **The slats keep a visible gap while listening.** Directed 2026-09-16: tweak the initial sizing and spacing of the slats and their listening size so that the spacing between them is more notable during Listening.
- **The app icon and any r-based glyph are dropped for now.** Decided 2026-09-16 after the font-outline rounds: "too big of a waste of time given disappointing results. Drop the menu bar r font/glyph approach altogether until we have an agent that can adequately design an icon/mark." The slat microphone glyph stays parked and approved as the menu bar mark; the work focuses on the indicators.

## Proposed, not confirmed

- The recording indicator panel stays charcoal regardless of macOS light or dark appearance, so the mark reads identically on any desktop.
- Using the accent on exactly one live element per surface. Superseded for marks by the uniform-ink decision above; still open for other surfaces.

## Open candidates

### Recording indicator: the enveloping bar (current focus)

The glyph is drawn by the same function as the menu bar, at 48 pt. Round nine opened its row pitch from 2.5 to 2.6 units and set the stroke to 1.1 at Ready and 1.3 awake (the menu bar had used 1.2 and 1.6), so the gaps between slats stay open while listening. The bar's outline is computed, not drawn ([studies/bar-shape.py](studies/bar-shape.py), which needs `shapely`): the slat silhouette offset outward by a constant 8 pt, joined to the 8 pt offset of the time's text box placed 6 pt to the right of the glyph column, with the concave junctions rounded at 5 pt. Three constructions are on the page:

- **Group outline offset** (chosen 2026-09-16): the offset of the group's convex outline, one smooth contour around the slats.
- **Silhouette offset**: the offset of every slat, so the edge follows each tip and scallops slightly along the sides.
- **Split**: the envelope and the time capsule as two separate shapes with a 6 pt gap.

At 48 pt with "0:00" at 12 pt the joined bar measures about 82 by 51 pt. The bar is filled with near-opaque charcoal (96% on light desktops, 94% on dark) and has no backdrop blur: browsers apply a backdrop filter to the element's rectangular box rather than to its clip path, which on a light desktop showed as two faint rectangles behind the glyph and the time (caught by the maintainer on 2026-09-16). The native implementation should clip its material to the shape or skip the material. Motion is ink only: a slat rises from 55% to full ink in about 0.15 s and settles over 0.6 s; the middle leads above level 0.06, the inner pair above 0.18, the outer pair above 0.55. Transcribing is the dotted glyph with the dots drifting right one pitch every 3.5 seconds (sped up from five at the maintainer's request), still under Reduce Motion. Solid and dotted are two layers crossfaded over about 0.2 s, so Listening to Transcribing never cuts hard; the bar itself fades in and out over 0.22 s with a 6 pt rise, ease-out both ways, instant under Reduce Motion. Nothing changes size.

**Open:** whether the 8 pt gap and 6 pt column gap are right, and whether the motion is now subtle enough; the maintainer accepted the construction without adjustments to either, so they stand until a live check says otherwise. Motion has only been judged in stills by the agent.

### Recording indicator: river (parked, still of interest)

Three strands, each a slow meander with a faster ripple at an irrational ratio, at their own amplitude, phase, and drift; both ends fade through a gradient mask; uniform ink. Motion above rest is round two's (attack rate 10, release rate 5), which the maintainer called "really fluid, really nice" at levels 0.5 and 1.0 and in the live transitions.

**Rest state, rebuilt 2026-09-16.** Round eight's rest state read as "grainy, pixelly, glitchy, rough". Diagnosis, confirmed in a full-scale capture: its amplitude at level 0 was 0.6 to 0.9 px on strokes of 1.3 to 2.6 px, rendered through a 0.9 scale, so near-horizontal hairlines crossed pixel rows at very shallow angles and antialiasing split their coverage between two rows; the slow drift then moved that pattern along the line. The rest state now has zero amplitude: three perfectly flat lines centered on pixel rows (1 px strokes on half-pixel y, the 2 px middle stroke on an integer y, the mark rendered 1:1 at 108 by 40), at 40% ink with a slow breath of plus or minus 6% over about seven seconds. Level blends width, ink, and amplitude into the motion over the first 0.15 of level with round two's timing. The maintainer chose the breathing variant over a frozen one, "assuming we can pull off smooth appearance"; the held rest frame is now crisp, and the breath awaits a live look.

### Menu bar glyph: river (parked, no verdict)

The redrawn channel glyph (one channel seen from above, wide at the near bank, one S-bend, tapering to a point; outline when Ready, filled when Listening, dotted banks when Transcribing) never got a read. It stays on the page beside the river indicator. The r-based menu bar glyphs tried on 2026-09-16 (a monoline r and a three-line r from Young Serif centerlines, and a filled Instrument Serif r) were dropped with the icon work; the two line-based ones had briefly been kept as candidates.

### App icon: dropped until an agent can design a mark

Nine attempts across two sessions, the last six being one subtle one-region flourish each on Besley, Niconne, and Scope One (capital and lowercase) taken point for point from the OFL outlines. The maintainer closed the line on 2026-09-16: "too big of a waste of time given disappointing results". The brief in [direction.md](direction.md) still stands for whoever picks it up; the method that held (take the outline, change one region, overlay the shipped outline, center on the ink box) is recorded in the rejected table and the working rules. The app ships the generic icon until then; nothing else in the identity depends on it.

### Accent: measured side by side

The accent never touches a mark (uniform ink), so it appears on the icon, on pressed controls and toggles, and on links. The study's Accent tab shows both candidates in every one of those places on light and dark grounds, with contrast against each ground:

| Pairing | Dark turquoise | Red sand |
|---|---|---|
| Accent text on white (needs 4.5:1) | 4.73:1 | 3.90:1, fails |
| Light variant on charcoal (needs 4.5:1) | 5.08:1 | 5.87:1 |
| White on accent, pressed control (needs 4.5:1) | 4.73:1 | 3.90:1, fails |
| Charcoal on the light variant, inverted icon (needs 3:1) | 5.08:1 | 5.87:1 |

Red sand `#C4674A` fails as text and as a control ground on white and would have needed darkening to about `#B0583C`. **Dark turquoise chosen 2026-09-16.** The study page keeps the red sand toggle only as the record of the comparison.

## Rejected, with reasons

| Attempt | Why it failed |
|---|---|
| Direction roll worlds: Caption Cell, Talkback, Type Specimen, Segment Mask, the category standard | Superseded by the maintainer's own direction: microphone grooves, river flow, an R-based mark |
| Round 1 indicators: grille as tributaries, R as a bend, symmetric braided channel | Read as "dots into lines"; the braid read as a woven basket, not a river |
| Microphone indicator, rounds 2 to 5: lines growing from center, a horizontal capsule, pillars, shimmer highlights, per-threshold stagger with dashes | Chaotic, jagged, "pillars to a building"; did not extend and recede with level |
| Microphone indicator, round 8: the capsule head measured from the reference photo (28 grooves, IoU 0.92) | Superseded 2026-09-16 by the maintainer's direction that the indicator is the menu bar glyph enlarged. The measurement stays in `studies/mic-groove-geometry.json` and `studies/measure-mic-grooves.py` as the record of the method |
| Round 9, first pass: the enlarged glyph inside the rounded-rectangle panel with the word "Listening", at 40 or 60 pt, with the stroke thickening to 1.6 while listening | "Neither": too much negative space around a roughly rectangular bar, centering problems, and the motion not subtle enough. Replaced the same day by the enveloping bar |
| Accent color on selected strokes; an emblem ring | Replaced by uniform ink and an empty emblem space |
| River wake-up with sharp attack and level-scaled speed | Far too snappy; reverted to round two's timing |
| River rest state as separated, nearly straight lines with a trace of drift (round 8) | Grainy and glitchy: sub-pixel wobble on hairlines, split between pixel rows by antialiasing and then drifted. Replaced by flat lines on pixel rows |
| River glyph as two banks or live strands | "Stock price chart", then "smashed tweezers"; not recognizable as a river |
| Accent: red sand `#C4674A` / `#DB8E70` | Fails contrast on white (3.90:1) as text and as a pressed-control ground; dark turquoise passes everywhere and was chosen |
| Icon: hand-drawn stroke R | Messy, hand-drawn |
| Icon: typeset R from a real font in a squircle | A reasonable start, but not bespoke, and not centered |
| Icon: computed capital R with a leg flourish | Looked like a broken glyph, not an intentional design |
| Icon: calligraphic lowercase r built from width profiles | Looked intentionally malformed |
| Icon: Young Serif r as the base outline | Not readable at icon sizes; dropped. Instrument Serif was the only legible base |
| Icon: the first Instrument Serif join edit, four points moved a few units | Invisible; the maintainer could not tell the modified glyph from the shipped one. Replaced by a visible S-taper join |
| Icon: Instrument Serif r with a large S-taper confluence filling the crotch | "Not a big fan of the large confluence approach"; too much |
| Icon: one subtle one-region flourish on each of Besley R and r, Niconne R and r, Scope One R and r | "Too big of a waste of time given disappointing results"; the icon and every r-based glyph dropped until an agent can design a mark |
| Menu bar: monoline r and three-line r from Young Serif centerlines | Briefly kept as candidates, then dropped with the icon work; the slat glyph is the menu bar mark |

## Working rules these rounds taught

1. **Look at every reference before drawing.** Two rounds were wasted drawing from a description of an image nobody had viewed.
2. **Measure when fidelity is the ask.** Extract geometry from the reference's pixels, score it (intersection-over-union per element), and verify with an overlay of the drawing on the reference. The microphone reached 92% only after this.
3. **Judge shape apart from motion.** Held frames at fixed levels beside the live element.
4. **Change one thing when asked to isolate.** A request to see the rest state "in isolation" means leave the timing alone.
5. **Stills cannot judge motion.** Say so, and ask the maintainer to watch it.
6. **The in-app browser captures only the first viewport.** Move the element under review to the top of the page before a screenshot, or the check silently sees nothing.
7. **Generating letterforms from scratch failed four times.** A bespoke icon letter is better started from a real, openly licensed font outline and modified in one place, not synthesized from curves. Round nine did this; the maintainer endorsed the approach.
8. **One drawing per mark.** When two surfaces must match (menu bar glyph and indicator), they call the same function at different sizes, so the match holds by construction rather than by comparison.
9. **The study page takes `?focus=<id>`.** It lifts one block to the top of the page and hides the header and controls, so the first-viewport screenshot sees it; use it instead of scrolling. The in-app browser cannot screenshot `file://` pages: serve the folder with `python3 -m http.server --directory <dir>` and open it over localhost.
10. **A backdrop blur does not follow a clip path.** A custom-shaped panel gets a near-opaque fill, or a material that is clipped natively; a CSS `backdrop-filter` under a `clip-path` draws its blur over the whole box and reads as a rectangle on light grounds.
11. **Hairlines must not wobble sub-pixel.** Any stroke under about 3 px that moves less than a pixel reads as grain, and drifting it reads as a glitch. A rest state is either exactly flat on a pixel row or clearly curved; there is no gentle in-between at that scale.
12. **Compute envelopes, don't draw them.** A bar that must hug a mark with a constant gap is the mark's offset (Minkowski sum with a disk), joined and closed with a fillet radius; `shapely` does this in a few lines and the result is exact.

## Impeccable state

`PRODUCT.md` exists (written 2026-09-16). The direction contract lives in the surface brief under `.impeccable/surfaces/`. DESIGN.md is deliberately not written yet: the `impeccable` flow writes it at the finish, from the built world. The direction round's seed key was `dd02b7c1`; the maintainer pinned their own direction over the roll. The mechanical detector was run once over the round-nine page; its only finding is the dark-appearance muted text token paired against the light panel, which is a token pairing older than this round and not part of any mark.
