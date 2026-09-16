# Design: Identity studies (locked 2026-09-16)

The state of River's identity exploration after eight rounds of interactive studies: what the maintainer confirmed, what is still a candidate, what was rejected and why, and the working rules the rounds taught. Read this before proposing any icon, glyph, indicator, or palette work, so rejected directions are not re-proposed and settled choices are not reopened.

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

## Proposed, not confirmed

- The recording indicator panel stays charcoal regardless of macOS light or dark appearance, so the mark reads identically on any desktop.
- Using the accent on exactly one live element per surface. Superseded for marks by the uniform-ink decision above; still open for other surfaces.

## Open candidates

### Recording indicator: microphone (current focus)

A capsule microphone head traced from a reference photo (source in [studies/mic-groove-geometry.json](studies/mic-groove-geometry.json)). Geometry is measured from the photo's pixels, not drawn by eye, and regularized to be symmetric:

- Head: rounded rectangle, 259 by 440 units, corner radius 62.
- Top group: six vertical slots, 22 wide on a 35 pitch, aligned along their lower ends; the inner four are 47 tall, the outer two 35 tall where the corners cut them.
- Middle group: eight rows, 31 tall on a 33.7 pitch, in two columns split by a central rib. The rib widens from 24 to 35 on the two rows where the emblem sat; the emblem itself is empty space.
- Bottom group: six vertical slots aligned along their upper ends; the inner four 92 tall, the outer two 77.
- **Fidelity:** 28 of 28 grooves, mean intersection-over-union 0.92 against the photo, lowest 0.83 on an outer slot where the photo's perspective breaks symmetry. Reproduce with [studies/measure-mic-grooves.py](studies/measure-mic-grooves.py).

Behavior: the silhouette is always drawn at 25% ink. Level wakes the groups bottom-up at thresholds 0.12, 0.42, and 0.72; within a group the center grooves lead. A groove rises to full ink in about 0.1 s and falls back in about 0.5 s. Transcribing holds every groove awake and breathes the head slowly.

**Open:** the portrait mark is small inside the 260 pt landscape panel (about 41 by 70 pt). Options are a taller panel, a larger mark, or accepting the size. The motion has only been judged in stills by the agent; it needs the maintainer's eye.

### Recording indicator: river

Three strands, each a slow meander with a faster ripple at an irrational ratio, at their own amplitude, phase, and drift; both ends fade through a gradient mask. Motion timing is round two's: attack rate 10, release rate 5. At rest the strands settle into three separated, nearly straight lines. The study page shows held frames at levels 0, 0.5, and 1.0.

**Open, awaiting the maintainer's read:** whether the rest state is right, and whether the peak frame is too busy. The faster wake-up variant was tried and rejected as "wayyy over the top".

### Menu bar glyph: river

Redrawn from a reference glyph: one channel seen from above, wide at the near bank, one S-bend, tapering to a point on the horizon. Outline when Ready, filled when Listening, filled with dotted banks when Transcribing. **Awaiting the maintainer's read.** The microphone glyph above is the accepted one.

### App icon: open

No attempt has been accepted. **The brief still stands:** inspired by a real type family, but bespoke, with one subtle flourish on a standard letterform; a simple serif lowercase r whose shoulder joins the stem like a tributary, curving and tapering naturally; perfectly centered in the squircle at every size. The attempts failed in execution, not in concept.

## Rejected, with reasons

| Attempt | Why it failed |
|---|---|
| Direction roll worlds: Caption Cell, Talkback, Type Specimen, Segment Mask, the category standard | Superseded by the maintainer's own direction: microphone grooves, river flow, an R-based mark |
| Round 1 indicators: grille as tributaries, R as a bend, symmetric braided channel | Read as "dots into lines"; the braid read as a woven basket, not a river |
| Microphone indicator, rounds 2 to 5: lines growing from center, a horizontal capsule, pillars, shimmer highlights, per-threshold stagger with dashes | Chaotic, jagged, "pillars to a building"; did not extend and recede with level |
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
7. **Generating letterforms from scratch failed four times.** A bespoke icon letter is better started from a real, openly licensed font outline and modified in one place, not synthesized from curves.

## Impeccable state

`PRODUCT.md` exists (written 2026-09-16). The direction contract lives in the surface brief under `.impeccable/surfaces/`. DESIGN.md is deliberately not written yet: the `impeccable` flow writes it at the finish, from the built world. The direction round's seed key was `dd02b7c1`; the maintainer pinned their own direction over the roll.
