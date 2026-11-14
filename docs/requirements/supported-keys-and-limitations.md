# Requirement: Supported Keys and Limitations

The dictation shortcut is a lone modifier (8 keys) or a combination, as listed in [activation-key-and-mode.md](activation-key-and-mode.md). This doc covers per-key behavior, known limitations, and which choices are refused, warned about, or accepted with caveats.

## Lone modifiers

### Right Control

The original default and the most "neutral" choice — rarely chorded with anything else, present on most external keyboards, fires `flagsChanged` reliably. Caveat: **MacBook built-in keyboards have no Right Control key.** Users on a MacBook with no external keyboard must pick a different key.

### Left Control

Reliable. May conflict with apps that use Left Control + key for shortcuts; this is unlikely to interfere because we listen to the modifier alone, but if the user is mid-chord with another key the activation may fire unexpectedly.

### Right / Left Option

Reliable. Right Option is the default. Same chord caveat as Left Control.

### Right / Left Command

Reliable. Cmd held alone is unusual in typical typing, so misfire risk is low. Caveat: holding Cmd briefly enters "spring-loaded" mode in some apps (Finder, Dock); for very long holds this may produce side effects.

### Right / Left Shift

Reliable. Caveat: macOS accessibility features (Sticky Keys, Slow Keys) interact with Shift. Users with those enabled should test before committing to Shift.

### Function (Fn) — keycode 63, the cancel key, not a dictation key

Fn cancels a recording ([0017](../planning/0017_cancel-recording.md)), so it is not offered as the dictation key (maintainer, 2026-11-12). The recorder refuses it as a key River already uses ("Cancel recording uses fn. Choose another."), and a saved Fn is dropped by the migration in favor of the default, as Caps Lock is. As the cancel key it keeps its hardware caveats:

- **MacBook built-in keyboards**: Fn often does fire `flagsChanged`, but on newer Macs Fn is also the Globe key and is bound to system features (Dictation, emoji picker, language switching), which may run on the same press.
- **External keyboards**: Magic Keyboards typically expose Fn as `flagsChanged`. Some third-party keyboards do not.

### Lone modifiers in Hold mode

A lone modifier can't tell a hold meant for dictation from the same key held while typing a shortcut with it. A River hot key pressed during the hold is the one case River can see: that recording is discarded silently ([activation-key-and-mode.md](activation-key-and-mode.md)).

### Caps Lock — not supported

River's tap sees one `flagsChanged` event for each Caps Lock press and none on release (measured 2026-11-06 in TextEdit: two presses held 2 s each gave two events and no release). Hold never sees the release, and a tap mode would need two presses for one tap. Caps Lock is therefore not offered, and a saved Caps Lock key is dropped by the migration in favor of the default. macOS also refuses it as a combination modifier.

## Combinations

A combination is a non-modifier key with one or more of ⌃ ⌥ ⇧ ⌘, held by River as an exclusive hot key.

- **No side.** A combination cannot tell left from right modifiers; a lone modifier still can.
- **No Caps Lock and no Fn** as a combination modifier.
- **macOS 15.0 and 15.1** refuse combinations whose only modifiers are ⌥ or ⌥⇧.
- **Taken by another app.** Registration fails when another app holds the same combination exclusively. River reports it as its own result (`eventHotKeyExistsErr`), so the shortcut is never silently dead.
- **macOS's own shortcuts** still fire alongside River's.

## What is refused and what is warned

Refused: what cannot work (Caps Lock, a key with no modifier, a combination macOS will not register) and what River already uses (Fn, which cancels a recording). Everything else is selectable in every mode, and no shortcut and mode pair carries a warning.

The principle: **inform, don't block**, except for River's own keys. The user knows their hardware better than the app does, but a key River already uses would do two things at once. **Why:** revised 2026-11-12 (maintainer). Fn as the dictation key turned its cancel off, which the Settings window had to explain, for a choice few would make once any key can be recorded.

## Macroscopic macOS limitations

These constrain the design as a whole:

- **No way to enumerate other apps' non-exclusive hotkeys.** Only an exclusive clash is reported at registration. Other conflicts with system shortcuts or other apps' global hotkeys must be discovered empirically. See [../conventions/anti-patterns.md](../conventions/anti-patterns.md).
- **Accessibility permission cannot be auto-granted.** macOS requires the user to manually add the app to System Settings → Privacy & Security → Accessibility. The app can only direct them there. See [../architecture/permissions.md](../architecture/permissions.md).
- **Tap-based modes have ~50–100 ms latency** versus Hold mode, because they require waiting for a complete tap (press + release) before acting. This is acceptable for a dictation use case.

## Related

- [activation-key-and-mode.md](activation-key-and-mode.md) — the shortcut, modes, persistence and live apply
- [../research/shortcut-registration.md](../research/shortcut-registration.md) — how each kind of shortcut is registered, and the probes behind it
- [../architecture/threading-invariant.md](../architecture/threading-invariant.md) — why the event tap is reliable for the keys it does support
