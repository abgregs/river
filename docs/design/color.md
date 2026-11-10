# Design: Color

The roles River's colors play, what the one accent means, and how a new surface chooses color. The tokens live in `Palette` (`Sources/River/Views/Palette.swift`); every value below was measured on 2026-09-26, the dark accent on 2026-10-09, the opaque HUD surfaces on 2026-11-04, and the menu bar's red modelled on 2026-11-04 (WCAG 2.x contrast; OKLCH from the sRGB hex). Read before adding color to any surface.

## The system in one sentence

Charcoal and ink carry everything, the mark included; one turquoise accent means **on**: a control you have switched on or are acting on. The one other hue is the menu bar's recording dot (below).

## Tokens

| Token | Value | OKLCH | Role |
|---|---|---|---|
| `charcoal` | `#23262B` | 26.8% 0.010 261 | The app icon's ground; text and the mark on the light HUD |
| `raisedCharcoal` | `#2E3238` | 31.6% 0.012 258 | A fill nested on charcoal |
| `deepCharcoal` | `#101215` | 18.0% 0.007 261 | The dark HUD's opaque tint: charcoal's hue, darker |
| `mist` | `#F4F5F7` | 97.0% 0.003 265 | The light HUD's opaque tint: charcoal's cool hue at near white |
| `ink` | `#ECEEF1` | 94.8% 0.005 258 | Every mark and all text on charcoal, the dark HUD included |
| `accentDark` | `#00E7E9` | 84.1% 0.143 196 | The accent on dark surfaces |
| `accentLight` | `#148284` | 55.2% 0.090 197 | The accent on light surfaces |
| `accent` | dynamic | — | Resolves to the light or dark value per appearance; the tint of the Settings and onboarding windows |
| `onAccent` | dynamic | — | Text on an accent fill: white on the light value, charcoal on the dark |
| `akane` / `akaneOnDark` | `#B13546` / `#DD6871` | 51.8% 0.159 17 / 66% 0.147 17 | The menu bar's recording dot on a light and on a dark bar (`recording` resolves between them); see Status colors |

## What the accent means: on

The accent marks something that is **on right now**: a control you turned on. It answers "what is engaged, what did I turn on", and nothing else.

**Where it appears**

- **Controls, through the SwiftUI tint** (`RiverApp`, `OnboardingCoordinator`): a switch that is on, a selected row or segment, the one primary button in a view, links. The color stays as long as the state holds; it is the state, not an event.
- **Platform-drawn progress** in the app's windows, which macOS tints from the same accent.

**Where it never appears**

- **The floating panel.** The mark and the Glass recording indicator draw in the HUD's text color (`ink` or `charcoal`) at a few strengths, from the press until the panel fades ([kawa-identity.md](kawa-identity.md)).
  **Why:** revised 2026-11-02 with the kawa identity, on the maintainer's direction that the panel be monochrome (2026-10-29). From 2026-10-14 the mark took the accent while River recorded or transcribed, one color for "River is on" ([stones-identity.md](stones-identity.md)); with 川 the panel says it in motion and in the ink's strength instead: muted strokes while River waits, the style's layer once it hears you. An accent glow offered in the motion study was dropped with the glow (2026-10-30).
- **River getting ready.** Preparing the model and any download stay neutral: in the panel the muted strokes held still, in the menu bar their SF Symbols. Nothing is being dictated yet.
- **Status.** Errors, warnings, and success are not "on". See Status below.
- **Confirmation flashes.** A setting that was just changed does not flash turquoise; the switch staying on is the confirmation.
- **The menu bar, and the app icon.** Every menu bar glyph is the mark the system paints white or black like the icons beside it, with one exception, the recording dot (Status colors); the icon is ink on charcoal "for now" ([identity-studies.md](identity-studies.md)). If the accent ever reaches the icon, the website, or the DMG, it is brand color outside the app's interface, where no state is implied.
  **Why:** revised 2026-10-15. The Active bars shipped in the accent, an image per Light and Dark mode, but the menu bar takes its look from the wallpaper behind it, not from the mode: in Light mode over a dark wallpaper the bar turned a mid blue-grey, every other icon went white, and the light accent measured about 1.5:1 there (white: 3.0:1). The maintainer chose to match the other icons.
- **Decoration.** No accent backgrounds, gradients, section headers, large fills, or static text. Accent text that does nothing reads as clickable.

## Which value to use

- **The HUD** takes no accent since 2026-11-02: `Palette.HUD` carries the tint and the text color per appearance, and the mark draws in the text color (see The HUD surface below).
- **App windows** (Settings, onboarding, menus) follow the system appearance, so they use the dynamic `accent`: `accentLight` measures 4.61:1 on white.
- **Text on an accent fill** uses `onAccent`: white on `accentLight` is 4.61:1; on `accentDark` white is 1.54:1 and fails, so the dark value takes charcoal (9.83:1).
- Never `accentLight` on charcoal or `accentDark` on white; measure any new pairing before shipping it.

## Neutrals and text

- **HUD:** `ink` on `deepCharcoal` measures 16.14:1 and `charcoal` on `mist` 13.91:1, the same over any desktop now that the surface is opaque. Secondary text (a toast's hint, the notice) is the text color at 80% (`hudSecondaryTextOpacity`): 10.51:1 on the dark tint and 7.49:1 on the light one. `PaletteTests` holds both to 4.5:1 on the tint.
  **Why:** revised 2026-10-16. It used the system `.secondary`, which renders the text color at 50%: about 3.0:1 on the light surface and 3.71:1 on the dark one's lightest measured ground. In the worst case the light surface needs 70% and the dark 80%, so one value covers both.
- **App windows:** platform label colors (`.primary`, `.secondary`) on system backgrounds. Do not paint windows charcoal; platform first ([direction.md](direction.md)).

## The HUD surface

Every floating surface (the mark's panel, the message rectangle, the transcript panel) is one `HUDSurface`: an opaque sheet in the system's appearance, lit as a solid pane of glass from the upper left. Its colors are `Palette.HUD`, one set per appearance; its values are the lit-edge block in `Constants`, chosen on the Glass study (maintainer, 2026-11-03; the page stays local).
**Why:** revised 2026-11-04 (maintainer). The surface was a translucent tint over a blur (72% `deepCharcoal`, 88% `mist`), so its ground, and every contrast on it, varied with the desktop behind it; the maintainer asked for a crisper, more solid glass look (2026-11-03). Opaque, it is crisp and high-contrast and looks the same over any desktop, so nothing behind it changes how the mark or the text reads. It follows Light and Dark mode, as it has since 2026-10-15.

- **Tint:** `deepCharcoal` in Dark mode, `mist` in Light, opaque. Reduce Transparency changes nothing.
- **Fading out:** the light mark panel is flattened before it fades, so it fades as one sheet. Faded layer by layer, the rim, where several layers stack, outlasted the fill: over a dark desktop the bright rim stood out as the panel left (on device, 2026-11-04). The dark panel fades layer by layer as approved.
- **The light:** one direction, `hudLightAngle` (147° in CSS terms, from the upper left). Every gradient on the surface runs along it, whatever the shape's proportions, and Glass's ripples are lit from it too, so the mark and its panel share one light (`HUDSurface.lightDirection`).
- **One edge with the Settings window (maintainer, 2026-11-09).** Settings is a native window with River's tint, so macOS draws its edge, and the floating surfaces match it rather than the reverse:
  - **The message and the live text** wear the window's edge: the tint with no sheen, rim or inner shade; in Dark a 0.5 pt inner line of 22 % white; a 0.5 pt outer line of 85 % black in Dark and 22 % in Light; and the window's shadow. Each keeps its own corner.
  - **The recording indicator** keeps the lit glass below (sheen, inner shade, its own two shadows), with the window's lines: in Dark the rim is a 0.5 pt line of 22 % white at the lit corner, fading to 8 % at the far one, so it is never brighter than a window's edge; the outer line is 85 % black in Dark and 22 % in Light.
  **Why:** a 1 pt rim that reached 93 % white, set as shares of the surface, grew into a heavy line down half a large panel, and the indicator's edge outshone the window beside it. Chosen on the settings panel study, rounds 9 to 12 (the page stays local). The bullets below describe the edge before this change; the build replaces their rim and outer-line values.
- **Under the content:** a white sheen from the lit corner (8.5% dark, 50% light), gone halfway across; two shadows falling straight down, as every window's do: a wide soft one and a tight one where the panel meets the desktop.
- **Over the content,** so neither text nor the frost covers the edge: a soft shade inside the far edges, a 1 pt rim of white brightest at the lit corner that dies away along the edges into a black shade at the far one, and a 0.5 pt dark outer line that holds the edge over light desktops (60% black dark, 14% light). Light mode runs the rim and sheen brighter and the shades lighter, since white only shows on a light tint near full strength.

## The mark's colors

The mark is the HUD's text color at a few strengths ([kawa-identity.md](kawa-identity.md)). Modelled 2026-11-04 (WCAG 2.x, the color mixed at its opacity over the opaque tint); a graphic that carries meaning needs 3:1. Glass's shader blurs and veils the frosted strokes as well, which this model leaves out.

| Strength | `deepCharcoal` (`ink`) | `mist` (`charcoal`) | Carries |
|---|---|---|---|
| Glass's ink where cleared (90%) | 13.14:1 | 10.35:1 | River hears you |
| Glass's ink under the frost (45%) | 4.06:1 | 2.65:1 | The voice's layer in silence |
| Muted (20%) | 1.75:1 | 1.48:1 | Waiting: preparing, before audio flows, a dead microphone, transcribing |

Glass's cleared ink carries "River hears you" and clears 3:1 on both tints. The frosted ink falls below 3:1 on the light tint; whether it needs a lift is open. The muted strokes, at the approved strength (maintainer, 2026-11-02), sit below it: the panel itself shows that River is on, and while the model prepares the label above it speaks. Whether the muted strokes need a lift under Increase Contrast is open. The stones' rule, solid and never below 3:1 with no Increase Contrast floor, no longer holds ([stones-identity.md](stones-identity.md); [pixel-identity.md](pixel-identity.md) recorded the earlier dimmed values).

Glass's veil, the light its ripples catch, and the shade on their far side are `Palette.HUD` colors too. The veil is the tint moved 16 % toward the text color in both appearances: `ink` over `deepCharcoal`, `charcoal` over `mist`. A ripple's lit side moves toward the text color and its far side toward the tint pushed away from it (40 % in Dark): `ink` and a deeper tint over `deepCharcoal`; over `mist`, `charcoal` lifted 35 % toward the tint and the tint blended 20 % toward white, both lifted toward the tint after full strength read too dark on device. Light's amounts are larger (0.95 and 0.15, against Dark's 0.55 and 0.5) so that its ripples measure as strong as Dark's: the shader mixes in linear light, where charcoal over the light tint shows about half as strongly as the same fraction of ink over the dark one.
**Why:** revised 2026-11-04, after the on-device check of the light entrance. The light veil was a near-white past `mist`, so the frost never showed on the light tint: the strokes went from muted to frosted with nothing visibly forming over them, where the dark frost visibly forms. The entrance's pulse in both appearances was the ink, not the veil ([kawa-identity.md](kawa-identity.md)). The light ripples were white light and a `charcoal` shade at 0.75 and 0.22; measured on rendered frames, they showed at about a quarter of Dark's strength (mean 3 L* against 12), so the maintainer asked for them to match (2026-11-04).

## Status colors

One: while River records a dictation (`.recording`), the menu bar's Listening glyph carries a dot in **akaneiro** (茜色), a muted madder red, the convention for a device that is recording (maintainer, 2026-11-04). In ready mode the microphone stays open while River is idle ([../planning/0033_warm-microphone-pre-roll.md](../planning/0033_warm-microphone-pre-roll.md)) and macOS shows its own indicator; River's red marks the dictation. It is `Palette.recording`: `akane` `#B13546` on a light bar, and `akaneOnDark` `#DD6871` (the same OKLCH hue, 17°, lifted to lightness 0.66) on a dark one. Modelled on the bar's grounds, the dot needs 3:1: `#B13546` measures 3.05:1 on a mid-gray `#B8B8B8` and 4.72:1 on `#E3E3E3`; `#DD6871` measures 3.36:1 on `#3A3B3D` and 4.99:1 on `#1E1E20`. A bar tinted mid-gray by a dark wallpaper defeats any red, and white icons barely reach 3:1 there; the dot's shape and the menu's "Recording..." carry the state, so color is never the only cue. Transcribing's dot is the bar's text color at 55 % (`menuBarMutedDotOpacity`), the least that holds 3:1 on the same modelled grounds (3.08:1 on `#B8B8B8`, 3.82:1 on `#3A3B3D`). Not yet measured on device. Otherwise error toasts are plain prose and the menu bar warning is a template symbol. When a feature genuinely needs one, use the macOS system colors, which adapt to appearance and Increase Contrast: red for errors and destructive actions, orange for warnings. Success gets no color; the typed text is the confirmation. Never system teal or cyan: teal sits at hue 217, 21° from the accent's 196, close enough to read as River's own color.

## Adding a color

Only when two things must be told apart at a glance and shape, text, or position cannot do it. Record the decision here as a revision, as round ten did for the meter ([pixel-identity.md](pixel-identity.md)) and the stones identity did for the accent's meaning ([stones-identity.md](stones-identity.md)). A new hue sits more than 15° from 196 and is measured against every surface it renders on. Color is never the only cue.

## Future surfaces

| Surface | Color |
|---|---|
| Settings window | Tint only: switches that are on, the selected sidebar row, one primary button per pane. Neutral section headers and icons |
| Snippets | Platform selection; no per-snippet color coding |
| Streaming text in the panel | The HUD's text color (`ink` or `charcoal`). A candidate under the earlier rule, open since the panel went monochrome (2026-11-02): words still being recognized in the accent (your voice, live), turning the text color once committed |
| History | Neutral; platform selection |
| Download progress | In the menu bar, its SF Symbol; in a window, the platform progress bar |
| Toasts and warnings | Prose in the HUD's text color; a status glyph, if added, takes system red or orange |

## Related

- [kawa-identity.md](kawa-identity.md) — the identity that took the accent out of the panel, and the menu bar's recording dot
- [stones-identity.md](stones-identity.md) — the identity that widened the accent to "River is on"
- [pixel-identity.md](pixel-identity.md) — the round that put the accent on the live meter
- [identity-studies.md](identity-studies.md) — how the turquoise was chosen, and the measured variants
- [direction.md](direction.md) — the principles this serves: platform first, quiet by default
