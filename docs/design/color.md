# Design: Color

The roles River's colors play, what the one accent means, and how a new surface chooses color. The tokens live in `Palette` (`Sources/River/Views/Palette.swift`); every value below was measured on 2026-09-26, the dark HUD surface and the dark accent on 2026-10-09, and the light HUD modelled on 2026-10-15 (WCAG 2.x contrast; OKLCH from the sRGB hex). Read before adding color to any surface.

## The system in one sentence

Charcoal and ink carry everything; one turquoise accent means **on**: River recording or transcribing your dictation, or a control you have switched on or are acting on. There is no second hue.

## Tokens

| Token | Value | OKLCH | Role |
|---|---|---|---|
| `charcoal` | `#23262B` | 26.8% 0.010 261 | The app icon's ground; text and the preparing r on the light HUD |
| `raisedCharcoal` | `#2E3238` | 31.6% 0.012 258 | A fill nested on charcoal |
| `deepCharcoal` | `#101215` | 18.0% 0.007 261 | The dark HUD's tint (72%) over its blur, and its opaque fill under Reduce Transparency: charcoal's hue, darker |
| `mist` | `#F4F5F7` | 97.0% 0.003 265 | The light HUD's tint (88%) over its blur, and its opaque fill under Reduce Transparency: charcoal's cool hue at near white |
| `ink` | `#ECEEF1` | 94.8% 0.005 258 | Every mark and all text on charcoal, the dark HUD included |
| `accentDark` | `#00E7E9` | 84.1% 0.143 196 | The accent on dark surfaces, the dark HUD included |
| `accentLight` | `#148284` | 55.2% 0.090 197 | The accent on light surfaces, the light HUD included |
| `accent` | dynamic | — | Resolves to the light or dark value per appearance; the tint of the Settings and onboarding windows |
| `onAccent` | dynamic | — | Text on an accent fill: white on the light value, charcoal on the dark |

## What the accent means: on

The accent marks something that is **on right now**: a dictation River is working on, or a control you turned on. It answers "what is live, what is engaged, what did I turn on", and nothing else.

**Where it appears**

- **The mark while River is active** ([stones-identity.md](stones-identity.md)). In the panel, the stones and the bars from the press until the panel fades, for Listening and Transcribing alike.
  **Why:** revised 2026-10-14 with the stones identity. The rule was "your voice": only the live meter took the accent, and River's own work (transcribing) stayed ink. The maintainer reads one color for "River is on"; the panel's motion, not its color, tells listening from transcribing.
- **Controls, through the SwiftUI tint** (`RiverApp`, `OnboardingCoordinator`): a switch that is on, a selected row or segment, the one primary button in a view, links. The color stays as long as the state holds; it is the state, not an event.
- **Platform-drawn progress** in the app's windows, which macOS tints from the same accent.

**Where it never appears**

- **River getting ready.** Preparing the model and any download stay neutral: in the panel the r held still in the HUD's text color (`ink` or `charcoal`), in the menu bar their SF Symbols. Nothing is being dictated yet.
- **Status.** Errors, warnings, and success are not "on". See Status below.
- **Confirmation flashes.** A setting that was just changed does not flash turquoise; the switch staying on is the confirmation.
- **The menu bar, and the app icon.** Every menu bar glyph, the Active bars included, is a template image the system paints white or black like the icons beside it; the icon is ink on charcoal "for now" ([identity-studies.md](identity-studies.md)). If the accent ever reaches the icon, the website, or the DMG, it is brand color outside the app's interface, where no state is implied.
  **Why:** revised 2026-10-15. The Active bars shipped in the accent, an image per Light and Dark mode, but the menu bar takes its look from the wallpaper behind it, not from the mode: in Light mode over a dark wallpaper the bar turned a mid blue-grey, every other icon went white, and the light accent measured about 1.5:1 there (white: 3.0:1). The maintainer chose to match the other icons.
- **Decoration.** No accent backgrounds, gradients, section headers, large fills, or static text. Accent text that does nothing reads as clickable.

## Which value to use

- **The HUD** follows Light and Dark mode through `Palette.HUD`: `accentDark` on the dark surface, `accentLight` on the light one (see The HUD surface below).
- **App windows** (Settings, onboarding, menus) follow the system appearance, so they use the dynamic `accent`: `accentLight` measures 4.61:1 on white.
- **Text on an accent fill** uses `onAccent`: white on `accentLight` is 4.61:1; on `accentDark` white is 1.54:1 and fails, so the dark value takes charcoal (9.83:1).
- Never `accentLight` on charcoal or `accentDark` on white; measure any new pairing before shipping it.

## Neutrals and text

- **HUD:** `ink` on the dark surface measures 9.65:1 on its lightest ground and 13.06:1 on charcoal (11.09:1 on raised charcoal); `charcoal` on the light surface, at least 10.6:1 by the worst-case model below. Secondary text (a toast's hint, the notice) is the text color at 80% (`hudSecondaryTextOpacity`), measured from a render: at least 4.85:1 on the dark surface and 6.26:1 on the light one in the worst case below. `PaletteTests` holds it to 4.5:1 with the text and the mark.
  **Why:** revised 2026-10-16. It used the system `.secondary`, which renders the text color at 50%: about 3.0:1 on the light surface and 3.71:1 on the dark one's lightest measured ground. In the worst case the light surface needs 70% and the dark 80%, so one value covers both.
- **App windows:** platform label colors (`.primary`, `.secondary`) on system backgrounds. Do not paint windows charcoal; platform first ([direction.md](direction.md)).

## The HUD surface

Every floating surface (the mark's panel, the message rectangle, the transcript panel) is one `HUDSurface`, built like a native HUD window in the system's appearance. Its colors are `Palette.HUD`, one set per appearance, and the blur's `NSVisualEffectView` takes the same appearance as the tint, so the two always flip together.
**Why:** revised 2026-10-15. The HUD was dark on every desktop, so its palette never flipped; the maintainer chose a light frosted surface in Light mode, the same build with light and dark swapped, which also matches the system's own pop-ups.

**Dark**, matched to Raycast Notes on 2026-10-09: `deepCharcoal` at 72% over the blur, a 1 pt inner hairline of white at 20% that brightens to 35% along the top edge, a 0.5 pt outer line of black at 80%, and one soft shadow outside the edge. Because the blur lets the desktop through, the ground varies with what is behind it. Measured on screen:

| Behind the surface | Ground | `ink` | `accentDark` |
|---|---|---|---|
| Black | `#131315` | 15.96:1 | 12.02:1 |
| 50% gray | `#262729` | 12.86:1 | 9.69:1 |
| White, the lightest case | `#3A3B3D` | 9.65:1 | 7.27:1 |

**Light**, 2026-10-15: `mist` (`#F4F5F7`, charcoal's hue at near white) at **88%** over the blur, text in `charcoal`, the mark in `accentLight`, the inner hairline white at 50% brightening to 90% (a sheen; white barely shows on a light tint), the outer line black at 12%, the same shadow. Not yet measured on screen; worst case, with the tint mixed straight over the desktop and the blur ignored:

| Behind the surface | `charcoal` | `accentLight` |
|---|---|---|
| Black, the darkest case | 10.63:1 | 3.23:1 |
| 50% gray | 12.27:1 | 3.73:1 |
| White | 14.04:1 | 4.26:1 |
| `mist`, opaque | 13.91:1 | 4.23:1 |

**Why 88%, not the dark surface's 72%:** a light panel over a dark desktop turns gray, and at 72% the deep accent fell to 2.13:1 over black. `PaletteTests` holds both appearances to 4.5:1 for text and 3:1 for the mark on this worst case, and fails at 72%. The hairline and outer-line values are first values; they passed the maintainer's on-device smoke on 2026-10-15 unchanged.

Under Reduce Transparency, the tint, opaque, replaces the blur and the tint, so the surface reads as the same panel as the blurred one.

## The mark's colors

Measured over the HUD surface's lightest ground (`#3A3B3D`, over a white page) and over `deepCharcoal` (the Reduce Transparency fill); a graphic that carries meaning needs 3:1 on both.

| Color | Lightest ground | `deepCharcoal` | Carries |
|---|---|---|---|
| `accentDark` | 7.27:1 | 12.16:1 | River active: the stones and the bars |
| `ink` | 9.65:1 | 16.14:1 | Preparing: the r held still |

On the light surface the same roles take `accentLight` and `charcoal`, at the values in the light table above.

The mark is solid: the pixel identity's dimmed cells, crest base, and dither are gone, so nothing in it sits below 3:1 and Increase Contrast needs no floor ([pixel-identity.md](pixel-identity.md) recorded those values).

## Status colors

River has none today: error toasts are plain prose and the menu bar warning is a template symbol. When a feature genuinely needs one, use the macOS system colors, which adapt to appearance and Increase Contrast: red for errors and destructive actions, orange for warnings. Success gets no color; the typed text is the confirmation. Never system teal or cyan: teal sits at hue 217, 21° from the accent's 196, close enough to read as River's own color.

## Adding a color

Only when two things must be told apart at a glance and shape, text, or position cannot do it. Record the decision here as a revision, as round ten did for the meter ([pixel-identity.md](pixel-identity.md)) and the stones identity did for the accent's meaning ([stones-identity.md](stones-identity.md)). A new hue sits more than 15° from 196 and is measured against every surface it renders on. Color is never the only cue.

## Future surfaces

| Surface | Color |
|---|---|
| Settings window | Tint only: switches that are on, the selected sidebar row, one primary button per pane. Neutral section headers and icons |
| Snippets | Platform selection; no per-snippet color coding |
| Streaming text in the panel | The HUD's text color (`ink` or `charcoal`). A candidate that fits the rule: words still being recognized in the accent (your voice, live), turning the text color once committed |
| History | Neutral; platform selection |
| Download progress | In the menu bar, its SF Symbol; in a window, the platform progress bar |
| Toasts and warnings | Prose in the HUD's text color; a status glyph, if added, takes system red or orange |

## Related

- [stones-identity.md](stones-identity.md) — the identity that widened the accent to "River is on"
- [pixel-identity.md](pixel-identity.md) — the round that put the accent on the live meter
- [identity-studies.md](identity-studies.md) — how the turquoise was chosen, and the measured variants
- [direction.md](direction.md) — the principles this serves: platform first, quiet by default
