# Design: Identity studies (round nine, 2026-09-16)

The state of River's identity exploration after nine rounds of interactive studies: what the maintainer confirmed, what is still a candidate, what was rejected and why, and the working rules the rounds taught. Read this before proposing any icon, glyph, indicator, or palette work, so rejected directions are not re-proposed and settled choices are not reopened.

The studies themselves are [studies/river-identity-studies.html](studies/river-identity-studies.html), a self-contained page: open it in a browser. The published copy is the maintainer's private artifact "River Identity Studies". The brief they serve is [direction.md](direction.md); product truth is [../../PRODUCT.md](../../PRODUCT.md).

## Confirmed by the maintainer

- **Palette: charcoal plus vivid turquoise.** Charcoal `#23262B`, raised charcoal `#2E3238`, ink `#ECEEF1`, accent vivid turquoise, hue 196 in OKLCH: `#148284` on light grounds (4.61:1 on white) and `#31C8CA` on dark grounds (7.40:1 on charcoal). Chosen 2026-09-16 from the variant grid, replacing the dark turquoise (`#1F7F86` / `#3FA3AA`) chosen earlier that day over red sand. On the dark value a pressed control takes charcoal text (white on it fails); on the light value white text passes.
- **Uniform ink on marks.** No selective accent color on individual strokes, "for now".
- **Rounded corners with concentric radii.** Outer radius equals inner radius plus padding, per `better-ui`. The studies use a 16 pt panel radius, 12 pt padding, 4 pt inner radius.
- **Presence while recording: small but unmistakable.**
- **Neither recording indicator carries a word.** "Listening" was dropped from the microphone bar and then from the river bar as redundant; the river bar also drops the timer, so it is lines only.
- **Untouched by this identity pass:** the menu bar dropdown, the Settings window layout, and the onboarding structure.
- **Anti-goals:** cute or mascot-like; the generic AI aesthetic (purple-blue gradients, sparkles, glowing orbs); heavy or decorative chrome. Literal water imagery was offered as an anti-goal and deliberately *not* chosen.
- **An indicator's empty and filled states are the same size.** State changes by ink, never by the shape growing or shrinking.
- **Menu bar glyph: the microphone slats.** Five horizontal slats, shortened toward the top and bottom, with distinct Ready, Listening, and Transcribing states (the Transcribing dots are real circles placed from both slat endpoints). Accepted as is: "this works, keep it, no edits"; parked as approved on 2026-09-16.
- **Recording indicator: the river, parked as approved (2026-09-16).** Three strands in a capsule bar, lines only; living rest state, level-driven listening, ink-crest transcribing, as described under Open candidates. The microphone bar remains the built alternative.
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

At 48 pt with "0:00" at 12 pt the joined bar measures about 84 by 51 pt. The time column is measured to the digit ink (23.4 pt wide at 12 pt SF Pro tabular), so the 8 pt padding holds on every side of the numerals, and its capsule is centered on the slat group's own center (row 9 of 16), which is also the bar's center; an earlier build had the capsule shifted one padding left and 3 pt high, which the maintainer read as the timer "squished against the right edge" (fixed 2026-09-16, verified by measurement in the browser). The bar is filled with near-opaque charcoal (96% on light desktops, 94% on dark) and has no backdrop blur: browsers apply a backdrop filter to the element's rectangular box rather than to its clip path, which on a light desktop showed as two faint rectangles behind the glyph and the time (caught by the maintainer on 2026-09-16). The native implementation should clip its material to the shape or skip the material. Width is fluid: past 10:00 the timer is five characters, and the bar switches to the envelope computed for that width (the page's `?elapsed=650` shows it); the native bar sizes the time column from the text's measured width. Motion is ink only: a slat rises from 55% to full ink in about 0.15 s and settles over 0.6 s; the middle leads above level 0.06, the inner pair above 0.18, the outer pair above 0.55. Transcribing is the dotted glyph, rebuilt after the maintainer's critique: each slat is a row of real circles (three, four, five, four, three at about a 2.5-unit pitch, dot radius equal to the Ready stroke's half width) whose first and last dots sit exactly on the slat's endpoints, so the dotted outline is the solid outline. In the indicator a soft cosine-shaped crest of full ink travels left to right across the dots every 2.4 s over a 55% base; no dot moves, appears, or disappears. In the menu bar the dots sit at full ink. Under Reduce Motion the crest stops at full ink. Solid and dotted are two layers crossfaded over about 0.2 s, so Listening to Transcribing never cuts hard; the bar itself fades in and out over 0.22 s with a 6 pt rise, ease-out both ways, instant under Reduce Motion. Nothing changes size.

**Open:** whether the 8 pt gap and 6 pt column gap are right, and whether the motion is now subtle enough; the maintainer accepted the construction without adjustments to either, so they stand until a live check says otherwise. Motion has only been judged in stills by the agent.

### Recording indicator: river (parked as approved, 2026-09-16)

Three strands, each a slow meander with a faster ripple at an irrational ratio, at their own amplitude, phase, and drift; both ends fade through a gradient mask; uniform ink. Motion above rest is round two's (attack rate 10, release rate 5), which the maintainer called "really fluid, really nice" at levels 0.5 and 1.0 and in the live transitions.

**Rest state, rebuilt twice on 2026-09-16.** Round eight's rest state read as "grainy, pixelly, glitchy, rough". Diagnosis, confirmed in a full-scale capture: its amplitude at level 0 was 0.6 to 0.9 px on strokes of 1.3 to 2.6 px, so near-horizontal hairlines crossed pixel rows at very shallow angles and antialiasing split their coverage between two rows; the slow drift then moved that pattern along the line. The first fix made the rest state three flat, pixel-aligned lines, which was crisp but which the maintainer then found too dead: "retain the aliveness and undulating waves that we have at the 0.50 level", slower and slightly compressed, not thin and straight.

The rest state now is a calmer 0.5: amplitude and stroke width have a floor at the level-0.35 values (70% of 0.5's amplitude, stroke just under 0.5's width), the drift runs at 45% speed at rest and speeds up smoothly with level, and the ink dims to 44% with a slow breath of plus or minus 6% over about seven seconds (the breath's low point measures about 3.15:1 on charcoal; it holds still under Reduce Motion). Ink is the only thing that says "resting"; the water never stops. The amplitude floor is about 2.7 px on the thinnest strand, which keeps every strand out of the sub-pixel band that caused the grain. Ink follows the level through a smoothstep over the first half of the range, so on release it settles in step with the motion (the first build blended ink only below level 0.15, which the maintainer saw as a late, abrupt opacity step). Transcribing holds the level at 0.4 and, after three attempts on 2026-09-16, leaves the lines untouched and moves the ink. The level-only state was "not distinct enough"; evenly spaced beads riding the strands were "just sort of weird"; the line morphing into three or four pulsing segments per strand was executed as asked but "feels broken/off". The maintainer then floated color (the accent instead of ink) and set it aside himself because color must not be the only cue, and proposed this: the previous three-line state with the ink flowing along the lines over a dimmed base, the "lines held, ink travels" analog of the dots experiments. The first build (a five-stop gradient stroke drawn over the base line, 54 px wide, 44% base, 2.4 s) read as "sparkly, sharp-contrasting, distracting": linear gradient stops put corners in the brightness ramp that read as edges, the overlay stroke summed with the base at its antialiased edges and haloed, and the dynamic range was too wide for the width. The polished build makes the crest a property of the one stroke: each strand is a single path stroked with a gradient in mark coordinates, a raised-cosine window 70 px wide sampled at 17 stops (smooth to the first derivative, so no corners), padded to the base ink beyond the band and slid left to right once every 2.0 s, each strand offset by 0.18 of the period. Only the stop opacities change with state, from all-full while listening to a 55% base with a full-ink crest while transcribing, blended over 0.2 s; there is no overlay, no composite, and no crossfade of two shapes, so nothing but the color moves. Distinct from rest (dim, no crest) and from listening (full ink following the voice) without color. Under Reduce Motion transcribing is the calm lines at full ink. Approved and parked on 2026-09-16 after a live read ("looks good"). The mark renders 1:1 at 108 by 40.

**Its own bar, 2026-09-16.** After the living rest state the maintainer called the river "a strong candidate" and asked for the same treatment as the microphone: a snug bar enclosing only the space the three lines need, no "Listening", and no timer at all. Because the strands move and a bar never changes size, the enclosure is the strands' full range of motion, the 108 by 40 band, plus 12 pt at the sides and 8 pt above and below (the sides widened from 8 at the maintainer's request so the lines breathe): a capsule 132 by 56 with 28 pt ends that follow the fade at the strands' ends. Same near-opaque fill, shadow, and 0.22 s fade with a 6 pt rise as the microphone bar. The page holds every stage at 2x (rest, 0.50, 1.00, transcribing) beside the live panel.

### Menu bar glyph: river (parked, no verdict)

The redrawn channel glyph (one channel seen from above, wide at the near bank, one S-bend, tapering to a point; outline when Ready, filled when Listening, dotted banks when Transcribing) never got a read. It stays on the page beside the river indicator. The r-based menu bar glyphs tried on 2026-09-16 (a monoline r and a three-line r from Young Serif centerlines, and a filled Instrument Serif r) were dropped with the icon work; the two line-based ones had briefly been kept as candidates.

### App icon: the slat mark ships; bespoke letterforms stay dropped

Nine attempts across two sessions, the last six being one subtle one-region flourish each on Besley, Niconne, and Scope One (capital and lowercase) taken point for point from the OFL outlines. The maintainer closed the line on 2026-09-16: "too big of a waste of time given disappointing results". The brief in [direction.md](direction.md) still stands for whoever picks it up; the method that held (take the outline, change one region, overlay the shipped outline, center on the ink box) is recorded in the rejected table and the working rules.

**An icon ships anyway, 2026-09-17.** The generic placeholder was unreadable in Finder, so the icon is the *approved slat mark* — ink on a charcoal squircle on Apple's 1024 grid, drawn by the same function as the menu bar glyph at a different size (working rule 8). No letterform, no new mark: the dropped work was inventing one, which this does not do. Ink and charcoal only, no accent, "for now" at the maintainer's call — a fuller accent pass is open. See [../planning/0028_identity-implementation.md](../planning/0028_identity-implementation.md).

### Accent: measured side by side

The accent never touches a mark (uniform ink), so it appears on the icon, on pressed controls and toggles, and on links. The study's Accent tab shows both candidates in every one of those places on light and dark grounds, with contrast against each ground:

| Pairing | Dark turquoise | Red sand |
|---|---|---|
| Accent text on white (needs 4.5:1) | 4.73:1 | 3.90:1, fails |
| Light variant on charcoal (needs 4.5:1) | 5.08:1 | 5.87:1 |
| White on accent, pressed control (needs 4.5:1) | 4.73:1 | 3.90:1, fails |
| Charcoal on the light variant, inverted icon (needs 3:1) | 5.08:1 | 5.87:1 |

Red sand `#C4674A` fails as text and as a control ground on white and would have needed darkening to about `#B0583C`. **Dark turquoise chosen 2026-09-16.** The study page keeps the red sand toggle only as the record of the comparison.

**Turquoise variants, 2026-09-16.** The maintainer asked to see more saturated, cyan-leaning, even neon variants in case the brand color moves. Nine were built in OKLCH (one hue each; chroma and lightness vary), each as a light-desktop value chosen as the most vivid value at that hue that still carries text at 4.5:1 on white, and a dark-desktop value for charcoal. Finding: the light values converge near chroma 0.095 (`#00818C`, `#148284`, `#02837E` and so on, all about 4.6:1), because sRGB cannot hold a cyan that is both vivid and dark enough for text on white. The variants differ on charcoal: from `#3FA3AA` at 5.08:1 through `#31C8CA` (7.4:1), `#3BCDDC` (7.9:1), `#00DDEF` (9.1:1), `#3FE4EC` (9.8:1) to `#14EEEE` (10.5:1). On any of the vivid dark values a pressed control needs charcoal text, since white on them fails. **Chosen 2026-09-16: Turquoise, vivid, hue 196** (`#148284` light, `#31C8CA` dark); the light appearance barely changes, the dark appearance gets the vivid accent and charcoal control text.

## Rejected, with reasons

| Attempt | Why it failed |
|---|---|
| Direction roll worlds: Caption Cell, Talkback, Type Specimen, Segment Mask, the category standard | Superseded by the maintainer's own direction: microphone grooves, river flow, an R-based mark |
| Round 1 indicators: grille as tributaries, R as a bend, symmetric braided channel | Read as "dots into lines"; the braid read as a woven basket, not a river |
| Microphone indicator, rounds 2 to 5: lines growing from center, a horizontal capsule, pillars, shimmer highlights, per-threshold stagger with dashes | Chaotic, jagged, "pillars to a building"; did not extend and recede with level |
| Microphone indicator, round 8: the capsule head measured from the reference photo (28 grooves, IoU 0.92) | Superseded 2026-09-16 by the maintainer's direction that the indicator is the menu bar glyph enlarged. The measurement stays in `studies/mic-groove-geometry.json` and `studies/measure-mic-grooves.py` as the record of the method |
| Transcribing as a dash pattern along each slat (rounds 2 to 9), drifting right in the indicator | Every row started flush left and ended where the pitch fell, so the right edge was ragged and the mark read as malformed beside Ready and Listening; drifting dashes pop at the path ends, leaving a jumping gap on the left. The agent had wrongly described the silhouette as unchanged. Replaced by centered circles and a traveling ink crest |
| River transcribing as evenly spaced round beads riding the strands, with an ink crest or a downstream drift | "Beads are just sort of weird here" |
| River transcribing as each line morphing into three or four pulsing segments with per-strand variation | Built exactly as asked, then "feels broken/off"; structure is the identity and must not change. Replaced by ink flowing along intact lines |
| River transcribing tinted in the accent instead of ink | Floated and set aside by the maintainer: color must not be the only cue; still possible later as a bonus over the ink crest, recorded as a deliberate revision if taken |
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
11. **Hairlines must not wobble sub-pixel.** Any stroke under about 3 px that moves less than a pixel reads as grain, and drifting it reads as a glitch. A rest state is either exactly flat on a pixel row or clearly curved with an amplitude floor of a few pixels; there is no gentle in-between at that scale. Signal "resting" with ink and speed, not with amplitude near zero.
12. **A dash pattern is not a row of dots.** Dashes start at the path's start and end wherever the pitch falls, so they align left and rag right, and they pop at the ends when offset. Dots that must share an outline with a solid stroke are drawn as circles placed from both endpoints.
13. **Check the timer at real lengths.** A five-character time is 28% wider than a four-character one; a capsule sized for "0:00" loses its right padding at 10:00. Every fixed-width text box in a mark needs its longest value tried.
14. **A moving highlight is a property of the stroke, not a thing on top of it.** Vary the one stroke's opacity along its length with a smooth window sampled at many stops; a second shape drawn over the first sums at its antialiased edges and reads as an object, and linear stops read as edges.
15. **Compute envelopes, don't draw them.** A bar that must hug a mark with a constant gap is the mark's offset (Minkowski sum with a disk), joined and closed with a fillet radius; `shapely` does this in a few lines and the result is exact.

## Implementation decisions (audit of 2026-09-16)

An audit of the prototype against the accessibility, color, typography, UI polish, Apple design, and animation lenses fixed four things on the page (five-character timer shape past 10:00; river rest ink 44% so the breath clears 3:1; breath still under Reduce Motion; ease-out on every fade) and settled these for the native build:

- **Bar surface:** near-opaque charcoal (96% on light desktops, 94% on dark), not a system material. The mark reads identically on any desktop; the opacity never flips the palette, and the shipping HUD's `.regularMaterial` is what this replaces.
- **Edge on dark grounds:** a 1 pt inner hairline of white at 7% following each bar's contour, shown only on dark desktops, where the shadow vanishes into windows the bar's own color. Not a high-contrast outline, which would be the decorative chrome the anti-goals name. The page's "Edge check, near-black ground" stages show the worst case for both bars.
- **Envelope geometry:** embed the outlines computed by [studies/bar-shape.py](studies/bar-shape.py) as point arrays (the four-character and five-character timer variants) drawn by a `Shape`; test by bounding box and point count. No live geometry code.
- **Menu bar template asset:** snap the 16 px asset's rows to device-pixel centers at 1x and 2x so the slats render crisp; the 48 pt indicator keeps the 2.6-unit pitch.
- **The shipping HUD's repeating mic pulse ignored Reduce Motion**; it was replaced by the new indicator rather than patched (done 2026-09-17: `RecordingIndicatorView` and its level meter are deleted).
- **Carry into the implementation:** every timing in `Constants` (0.15 s rise, 0.6 s fall, 0.2 s crossfade, 0.22 s fade with a 6 pt rise, 3.5 s dot drift, thresholds 0.06 / 0.18 / 0.55); the wake filter runs per frame (`TimelineView(.animation)`, paused when idle) because level publishes every 70 ms; `accessibilityLabel` for the state and `accessibilityValue` for the time; `accessibilityReduceMotion` turns the crossfade and fade instant and stills the dots; a pure `SlatPresentation` mapping tested with `@Test(arguments:)`.

## Impeccable state

`PRODUCT.md` exists (written 2026-09-16). The direction contract lives in the surface brief under `.impeccable/surfaces/`. DESIGN.md is deliberately not written yet: the `impeccable` flow writes it at the finish, from the built world. The direction round's seed key was `dd02b7c1`; the maintainer pinned their own direction over the roll. The mechanical detector was run once over the round-nine page; its only finding is the dark-appearance muted text token paired against the light panel, which is a token pairing older than this round and not part of any mark.
