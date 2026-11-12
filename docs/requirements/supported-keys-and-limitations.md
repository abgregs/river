# Requirement: Supported Keys and Limitations

The dictation shortcut is a lone modifier (9 keys) or a combination, as listed in [activation-key-and-mode.md](activation-key-and-mode.md). This doc covers per-key behavior, known limitations, and which choices are refused, warned about, or accepted with caveats.

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

### Function (Fn) — keycode 63

The Fn key may not produce `flagsChanged` events on all Apple keyboards. Behavior depends on:

- **MacBook built-in keyboards**: Fn often does fire `flagsChanged`, but on newer Macs Fn is also the Globe key and is bound to system features (Dictation, emoji picker, language switching). Holding Fn alone may trigger one of those system features before the app sees it.
- **External Apple keyboards**: Magic Keyboards typically expose Fn as `flagsChanged`. Some third-party keyboards do not.

Fn is also the cancel key ([0017](../planning/0017_cancel-recording.md)). When Fn is the dictation key, the fn cancel is off, because its press already means start or stop; the menu item still cancels.

A planned Settings warning will alert the user when Fn is selected. The key is included because some users specifically want it; it is the user's responsibility to verify it works on their hardware.

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

Only what cannot work is refused: Caps Lock, a key with no modifier, and a combination macOS will not register. Everything else is selectable in every mode. No shortcut and mode pair carries a warning today; a planned one covers Fn.

The principle: **inform, don't block.** The user knows their hardware better than the app does.

## Macroscopic macOS limitations

These constrain the design as a whole:

- **No way to enumerate other apps' non-exclusive hotkeys.** Only an exclusive clash is reported at registration. Other conflicts with system shortcuts or other apps' global hotkeys must be discovered empirically. See [../conventions/anti-patterns.md](../conventions/anti-patterns.md).
- **Accessibility permission cannot be auto-granted.** macOS requires the user to manually add the app to System Settings → Privacy & Security → Accessibility. The app can only direct them there. See [../architecture/permissions.md](../architecture/permissions.md).
- **Tap-based modes have ~50–100 ms latency** versus Hold mode, because they require waiting for a complete tap (press + release) before acting. This is acceptable for a dictation use case.

## Related

- [activation-key-and-mode.md](activation-key-and-mode.md) — the shortcut, modes, persistence and live apply
- [../research/shortcut-registration.md](../research/shortcut-registration.md) — how each kind of shortcut is registered, and the probes behind it
- [../architecture/threading-invariant.md](../architecture/threading-invariant.md) — why the event tap is reliable for the keys it does support
