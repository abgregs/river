# Bug: text lost when a long transcript is typed into Claude Code (0031)

A bug record. Reported by the maintainer on 2026-10-12 and diagnosed the same day. The fix is on branch `fix/paste-fidelity`.

## Symptom

When River inserted a transcript into Claude Code's TUI (VS Code's integrated terminal), part of the text was sometimes missing, and `[Pasted text #N]` placeholders sometimes appeared in the middle of it. "Copy last transcription", pasted with a real ⌘V, always arrived whole.

## The two deliveries hold the same text

`RiverSession.deliver(_:)` retains the transcript as `lastTranscript` and then types that same string; `copyLastTranscript` writes `lastTranscript`. Nothing transforms either copy. A test now pins it: a full cycle with emoji, a combining accent, and quotes types exactly the transcript, and "Copy last transcription" copies exactly what was typed.

## Cause

River does not paste. `TextInsertionManager` types the transcript as Unicode key events of 20 UTF-16 units ([0011](0011_keystroke-injection.md)), and posted them all back to back. A terminal writes each key event's text to the pty, so a long transcript reached the app as one burst.

Claude Code's input handler (read from its bundled source, version 2.1.296) treats any single read longer than 800 characters that is not wrapped in bracketed-paste markers as a paste (`key.length > 800`). A burst therefore arrived as several unmarked "pastes" mixed with typed text. Long ones became placeholders, and in that path about 2 KB went missing.

A real ⌘V takes a different route: the terminal wraps the clipboard in `ESC[200~ … ESC[201~`, and Claude Code collects it as one paste, whatever the read sizes. See [../research/terminal-paste-fidelity.md](../research/terminal-paste-fidelity.md) for the terminal side and its sources.

## Evidence

A throwaway loop ran the real `claude` binary in a pty. It wrote River's chunk stream into the pty one chunk per write, as a terminal does per key event. The text went in after `!` (bash mode), so Enter ran `printf` locally with no model call, and the file it wrote held exactly what the prompt held:

| Insert | Result |
|---|---|
| 300 or 1,200 characters, no gap | Whole |
| 2,500–3,000 characters, no gap | 5 of 6 runs lost exactly 2,044 characters, and the text after about 190 characters was out of order; the run that passed showed 3 placeholders |
| 3,000 characters, 1, 2, 4, or 5 ms between chunks; 6,000 at 5 ms | Whole in every run (13 of 13), no placeholders |
| 3,000 characters as one bracketed paste | Whole, one placeholder (what ⌘V does) |

A plain raw-mode reader that stalled during the burst received all 3,000 characters: the pty blocks the writer and loses nothing. So the loss is in Claude Code's handling of large unmarked input, not in the terminal layer the loop covered.

## Fix

`TextInsertionManager` waits `Constants.keystrokeChunkGapSeconds` (4 ms) between chunks, so the target reads the transcript a few chunks at a time. 1 ms was enough in every run; 4 ms leaves room for a busy Claude Code. It costs about 0.2 s per 1,000 characters, and it applies to every app, which keeps the no-clipboard design of 0011 intact.

Alternatives, not taken:

- **Pasteboard plus a synthetic ⌘V.** This reuses the lossless path, but it brings back the clipboard-restore race that 0011 removed.
- **Bracketed-paste markers typed as keys.** An ESC typed as a Unicode string is not a pty escape, and terminals wrap only real pastes.
- **A per-terminal strategy.** River cannot tell VS Code's terminal pane from its editor.

## Not covered by the loop

- **The synthetic event path itself:** `CGEvent` → VS Code (Chromium, xterm.js) → pty. The research raises one more suspect there: a multi-character key event losing all but its last character in xterm.js. River's field results argue against it, since most text arrives, but no loop has measured it.
- **Claude Code under load,** in a long conversation, where its reads are slower than in the fresh session the loop used.

## Verify on device

Dictate a long passage, 2,000 or more characters with streaming, into Claude Code in VS Code's terminal. The prompt should hold every word, in order, with no `[Pasted text #N]` placeholders. Compare it against "Copy last transcription" pasted into a text editor.

## Regression tests

- `TextInsertionFidelityTests`:
  - the typed text is the whole transcript, in order;
  - chunks are spaced at least 1 ms apart, never before the first chunk or after the last.
- `RiverSessionTests`: the typed text equals what "Copy last transcription" copies.

## Related

- [0011_keystroke-injection.md](0011_keystroke-injection.md) — why River types instead of pasting; the chunk gap was its open validation knob
- [0019_last-transcript-recovery.md](0019_last-transcript-recovery.md) — "Copy last transcription"
