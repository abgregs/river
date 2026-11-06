# Requirement: Activation Key and Mode

The user sets **one dictation shortcut** and **one mode**. The shortcut says which key starts and stops dictation; the mode says how. They are separate settings, both persisted to `UserDefaults` and applied live without restart.

## Modes

| Mode | Behavior |
|---|---|
| **Hold** (default) | Press → start recording. Release → stop and transcribe. |
| **Single Tap** | First complete tap → start recording. Next complete tap → stop and transcribe. |
| **Double Tap** | Two complete taps within a fixed ~400 ms window → start. A single complete tap → stop. |

A "complete tap" means press followed by release. Holding the shortcut in tap modes is treated as a single tap (no special behavior).

In Double Tap mode, stop requires only **one** tap, not another double tap. **Why:** requiring a second double-tap under time pressure is error-prone. Stopping a recording should be easy.

## The dictation shortcut

The shortcut is either a **lone modifier** or a **combination**. Every shortcut works in all three modes.

### Lone modifier

One of 9 modifier keys, watched on the listen-only event tap. A lone modifier keeps its side: left and right share a flag-mask family, so River tells them apart by keycode, not by flag bit. See [../architecture/configuration.md](../architecture/configuration.md).

| Key | Keycode | `CGEventFlags` mask |
|---|---|---|
| Right Control | 62 | `.maskControl` |
| Left Control | 59 | `.maskControl` |
| Right Option (default) | 61 | `.maskAlternate` |
| Left Option | 58 | `.maskAlternate` |
| Right Command | 54 | `.maskCommand` |
| Left Command | 55 | `.maskCommand` |
| Right Shift | 60 | `.maskShift` |
| Left Shift | 56 | `.maskShift` |
| Function (Fn) | 63 | `.maskSecondaryFn` |

Right Option is the default because it's present on every Mac keyboard (including MacBook and the compact Magic Keyboard, neither of which has a Right Control) and rarely pressed during typing, so Hold mode doesn't fire on capitalization or common shortcuts.

Caps Lock is not a dictation key. **Why:** River's tap sees one event for each Caps Lock press and none on release (measured 2026-11-06), so Hold never sees the release and a tap mode would need two presses per tap. See [supported-keys-and-limitations.md](supported-keys-and-limitations.md).

### Combination

A non-modifier key plus one or more of ⌃ ⌥ ⇧ ⌘, registered with `RegisterEventHotKey` as an exclusive hot key, so the app in front never receives it. A combination does not keep a side: ⌃⌥Space is the same shortcut with either Control or Option.

- **Hold** starts on the press. It stops on the key's release or on any of the combination's modifiers lifting, whichever comes first. The tap reports the modifiers lifting.
- **Single Tap and Double Tap** act on the key's release, so holding the combination is one tap.

### Another River shortcut during a lone-modifier press

When a River hot key is pressed while the lone-modifier dictation key is down (Right ⌥ held, then a River ⌃⌥ shortcut), the modifier belongs to that shortcut. In Hold, the recording that press started is discarded with no notice and no cue. In a tap mode, that press is not a tap. River does not refuse such shortcuts when they are recorded.

## Persistence

Declared as typed keys on the `Settings` namespace (backed by `UserDefaults.standard`):

| Key | Type | Default |
|---|---|---|
| `Settings.dictationShortcut` | `Shortcut` | Right Option (`mod:61`) |
| `Settings.activationMode` | `ActivationMode` | `.hold` |

A shortcut is stored as one string so `@AppStorage` can bind it: `mod:61` for a lone modifier, `key:49:ctrl,opt` for a combination. An empty string means cleared; the dictation shortcut cannot be cleared, so a cleared or unreadable value reads as the default.

**Migration.** Before v0.3.0 the key was `activationKeyCode`, an `Int`. At launch, a saved `activationKeyCode` that is one of the 9 lone modifiers becomes that `dictationShortcut`, unless one is already saved; any other value is dropped. The old key is then removed.

The double-tap detection window is **not** a user setting — it's a fixed internal `Constants.doubleTapWindowMs` (400 ms). The user shouldn't have to tune it, so there is no control for it. See [../architecture/configuration.md](../architecture/configuration.md).

See [../architecture/settings-store.md](../architecture/settings-store.md) for the typed read/write API and [../conventions/persistence.md](../conventions/persistence.md) for declaration conventions.

## Live apply

[`RiverSession`](../architecture/river-session.md) subscribes to `store.publisher(for: Settings.dictationShortcut)` and `Settings.activationMode`. When either emits a new typed value, the session applies it based on its state and the **active** mode:

- **Idle** → `HotkeyManager` swaps the shortcut or mode **in place**: a lone modifier is a keycode refilter while the one event tap keeps running (no rebuild, preserving the [threading invariant](../architecture/threading-invariant.md)); a combination moves its hot key registration.
- **Recording in a tap mode** → the change applies **live** and the recording continues. The new shortcut or mode immediately becomes the stop gesture, and the session posts a notice confirming the user can use it to stop the current recording. No audio is lost, because nothing tears down the running tap.
- **Recording in Hold mode, or processing** → the change is deferred and applied when the cycle returns to `.idle`. Hold defers because the user is physically holding the old shortcut, whose release must still stop the recording.

There is no path that tears down the event tap mid-cycle. See [../architecture/river-session.md](../architecture/river-session.md).

## Settings UI

Until the shortcut recorder lands in the settings panel ([0036](../planning/0036_settings-and-shortcuts.md)), the Activation section of Settings contains:

1. **Activation Key picker** — dropdown with the 9 lone modifiers above, as "Dictation shortcut" in the Settings window's Shortcuts section, until PR 8's recorder replaces it ([0036](../planning/0036_settings-and-shortcuts.md)). It writes `dictationShortcut`. A combination can be set only by the recorder.
2. **Activation Mode picker** — "Start by", a segmented choice of Hold / Tap / Double-tap, with the chosen mode's one-line description and the cancel line under it.

Warnings inform and never block: the user knows their keyboard better than the app does. No shortcut and mode pair carries a warning today. A planned one: Fn may conflict with the system Globe key on newer Macs.

## Related

- [supported-keys-and-limitations.md](supported-keys-and-limitations.md) — known macOS limitations per key
- [../architecture/configuration.md](../architecture/configuration.md) — how live-apply works under the hood
- [../conventions/persistence.md](../conventions/persistence.md) — UserDefaults key conventions
