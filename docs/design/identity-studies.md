# Design: Identity studies (round nine, 2026-09-16)

The state of River's identity exploration after nine rounds of interactive studies: what the maintainer confirmed, what is still a candidate, what was rejected and why, and the working rules the rounds taught. Read this before proposing any icon, glyph, indicator, or palette work, so rejected directions are not re-proposed and settled choices are not reopened.

The studies themselves are [studies/river-identity-studies.html](studies/river-identity-studies.html), a self-contained page: open it in a browser. The published copy is the maintainer's private artifact "River Identity Studies". The brief they serve is [direction.md](direction.md); product truth is [../../PRODUCT.md](../../PRODUCT.md).

## Confirmed by the maintainer

- **Palette family: charcoal plus one accent.** Charcoal `#23262B`, raised charcoal `#2E3238`, ink `#ECEEF1`. The accent is one of two, not yet chosen: dark turquoise `#1F7F86` (`#3FA3AA` on dark grounds) or red sand `#C4674A` (`#DB8E70` on dark grounds).
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
- **The app icon starts from a real font outline.** The maintainer endorsed the approach on 2026-09-16: take the vector outline of a real, openly licensed lowercase r and design off that shape.

## Proposed, not confirmed

- The recording indicator panel stays charcoal regardless of macOS light or dark appearance, so the mark reads identically on any desktop.
- Using the accent on exactly one live element per surface. Superseded for marks by the uniform-ink decision above; still open for other surfaces.

## Open candidates

### Recording indicator: the enveloping bar (current focus)

The glyph is drawn by the same function as the menu bar, at 48 pt. Round nine opened its row pitch from 2.5 to 2.6 units and set the stroke to 1.1 at Ready and 1.3 awake (the menu bar had used 1.2 and 1.6), so the gaps between slats stay open while listening. The bar's outline is computed, not drawn ([studies/bar-shape.py](studies/bar-shape.py), which needs `shapely`): the slat silhouette offset outward by a constant 8 pt, joined to the 8 pt offset of the time's text box placed 6 pt to the right of the glyph column, with the concave junctions rounded at 5 pt. Three constructions are on the page:

- **Group outline offset** (chosen 2026-09-16): the offset of the group's convex outline, one smooth contour around the slats.
- **Silhouette offset**: the offset of every slat, so the edge follows each tip and scallops slightly along the sides.
- **Split**: the envelope and the time capsule as two separate shapes with a 6 pt gap.

At 48 pt with "0:00" at 12 pt the joined bar measures about 82 by 51 pt. Motion is ink only: a slat rises from 55% to full ink in about 0.15 s and settles over 0.6 s; the middle leads above level 0.06, the inner pair above 0.18, the outer pair above 0.55. Transcribing is the dotted glyph with the dots drifting right one pitch every 3.5 seconds (sped up from five at the maintainer's request), still under Reduce Motion. Nothing changes size.

**Open:** whether the 8 pt gap and 6 pt column gap are right, and whether the motion is now subtle enough; the maintainer accepted the construction without adjustments to either, so they stand until a live check says otherwise. Motion has only been judged in stills by the agent.

### Recording indicator: river

Three strands, each a slow meander with a faster ripple at an irrational ratio, at their own amplitude, phase, and drift; both ends fade through a gradient mask. Round nine put all three strands in uniform ink (the middle strand had carried the accent, against the confirmed rule); shape and timing untouched. Motion timing is round two's: attack rate 10, release rate 5. At rest the strands settle into three separated, nearly straight lines. The study page shows held frames at levels 0, 0.5, and 1.0.

**Open, awaiting the maintainer's read:** whether the rest state is right, and whether the peak frame is too busy. The faster wake-up variant was tried and rejected as "wayyy over the top".

### Menu bar glyph: river

Redrawn from a reference glyph: one channel seen from above, wide at the near bank, one S-bend, tapering to a point on the horizon. Outline when Ready, filled when Listening, filled with dotted banks when Transcribing. **Awaiting the maintainer's read.** The microphone glyph above is the accepted one.

### App icon: from a real outline, one change

The lowercase r is taken point for point from an openly licensed face, and exactly one thing is changed: the inner join where the underside of the shoulder meets the stem. The font's short notch becomes a long concave sweep that arrives tangent to the stem well below the shoulder, so the shoulder reads as a tributary merging into the channel. Four contour points move; every other point is the font's. The study shows the change at three lengths (the font as shipped, the River join, a longer confluence), an overlay of the original outline on the modified letter, and Dock and Finder sizes.

- **Lead base: Young Serif** (Bastien Sozeau, SIL OFL 1.1). Its stem weight survives 16 px.
- **Alternate base: Instrument Serif** (Rodrigo Fuenzalida and Jordan Egstad, SIL OFL 1.1). Elegant at 128 px; its hairlines disappear at 16 px, and the same edit barely shows on it.
- Both outlines were taken from the google/fonts repository on 2026-09-16 and extracted with fontTools; the sources are not committed. The finished icon ships as a raster with its source outline and edit recorded.
- Centering is geometric on the ink box, both axes, at every size. The type research at `~/Developer/typography-research` notes that optical centers sit above mathematical ones for double-story letters; an optical nudge for the r is a separate decision for the maintainer, not applied.

**Awaiting the maintainer's read:** the base face, the confluence length, and whether the letter should sit in accent on charcoal (shown) or in ink.

### Accent: measured side by side

The accent never touches a mark (uniform ink), so it appears on the icon, on pressed controls and toggles, and on links. The study's Accent tab shows both candidates in every one of those places on light and dark grounds, with contrast against each ground:

| Pairing | Dark turquoise | Red sand |
|---|---|---|
| Accent text on white (needs 4.5:1) | 4.73:1 | 3.90:1, fails |
| Light variant on charcoal (needs 4.5:1) | 5.08:1 | 5.87:1 |
| White on accent, pressed control (needs 4.5:1) | 4.73:1 | 3.90:1, fails |
| Charcoal on the light variant, inverted icon (needs 3:1) | 5.08:1 | 5.87:1 |

Red sand `#C4674A` fails as text and as a control ground on white; if chosen, its light-appearance value needs darkening to about `#B0583C` before it carries text. **Awaiting the maintainer's choice.**

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
| River glyph as two banks or live strands | "Stock price chart", then "smashed tweezers"; not recognizable as a river |
| Icon: hand-drawn stroke R | Messy, hand-drawn |
| Icon: typeset R from a real font in a squircle | A reasonable start, but not bespoke, and not centered |
| Icon: computed capital R with a leg flourish | Looked like a broken glyph, not an intentional design |
| Icon: calligraphic lowercase r built from width profiles | Looked intentionally malformed |

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
10. **Compute envelopes, don't draw them.** A bar that must hug a mark with a constant gap is the mark's offset (Minkowski sum with a disk), joined and closed with a fillet radius; `shapely` does this in a few lines and the result is exact.

## Impeccable state

`PRODUCT.md` exists (written 2026-09-16). The direction contract lives in the surface brief under `.impeccable/surfaces/`. DESIGN.md is deliberately not written yet: the `impeccable` flow writes it at the finish, from the built world. The direction round's seed key was `dd02b7c1`; the maintainer pinned their own direction over the roll. The mechanical detector was run once over the round-nine page; its only finding is the dark-appearance muted text token paired against the light panel, which is a token pairing older than this round and not part of any mark.
