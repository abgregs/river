# Bug: first recording lost when the audio device changes mid-recording (0032)

A bug record. Diagnosed 2026-09-24 from a captured log trace during the 0029 smoke, listed as a known issue in v0.2.0 and v0.2.1, fixed 2026-10-22 on branch `fix/device-switch`. It is also the prerequisite for the warm microphone spec, which keeps an engine alive across every device change.

## Symptom

On the first activation after launch, the recording state and the hotkey behave normally, but no audio is captured: the meter never moves, nothing is transcribed, and no error is shown. The next activation works.

## Evidence (log, 2026-09-24 16:19, pid 25823)

- First recording: `AVAudioEngine started; input format 24000 Hz`. A 14 s recording produced 15 buffers (about 1.5 s of audio), all below the silence gate: `0 after silence trim`, a quiet no-op.
- Second recording: 48000 Hz, 89 buffers over 9 s (normal, about 100 ms per buffer).
- System trace from inside River's process: on the first engine start, CoreAudio built a default-device aggregate of the default input and the default output, which was the maintainer's AirPods Pro. Bluetooth Smart Routing put the AirPods into their call profile (HFP, 24 kHz: `GetBestSampleRate:24000`, `HFPInputShimDevice: StartIO`). About 1.7 s later: `HAL notification: default input device changed`, `default output device changed`, `AUHAL SelectDevice: stopping` — the aggregate was torn down and the engine's IO stopped.
- River never observed `AVAudioEngineConfigurationChange`, so the recording kept running with a dead engine. The next recording built a fresh engine on the new default device (the built-in mic, 48 kHz) and worked.

"First after launch" is incidental: the trigger is the default input or output changing while a recording is live. With AirPods connected, the first mic open triggers exactly that; after it settles, later recordings are stable.

## Fix

1. **Survive a configuration change.** `MicrophoneCapability` observes `.AVAudioEngineConfigurationChange` for its engine. On the change it re-reads the input format, reinstalls the tap, and restarts the engine in place, logging the new format. `AVAudioEngine.start` stays in that one capability (AGENTS.md rule 3). The observer is installed with the engine and removed by `stopEngine`, so a change can neither be missed during a recording nor restart an engine that was deliberately stopped. *Superseded 2026-10-26:* capture moved to a HAL output unit pinned to a device chosen by `InputDeviceSelection` (warm-microphone spec, decision 4). A pinned unit does not follow the default and the notification no longer exists; the capability listens to the HAL for default-input and device-list changes and re-pins only when the selection names a different device, so AirPods connecting or leaving while the built-in microphone is pinned costs no restart. Fixes 2–4 are unchanged.
2. **Convert mixed formats.** `AudioCaptureManager.convert` assumed every buffer shared the first buffer's format. After a restart the buffers change rate (24 kHz → 48 kHz) and would be resampled wrongly. `convert(_:toSampleRate:)` now splits the recording into runs of same-format buffers (`formatRuns`), converts each run with its own converter, and joins them.
3. **Never fail silently.** If the restart failed and the captured audio falls short of the recording's wall time by more than `Constants.captureGapMaximumSeconds` (1 s), `stopRecording` throws `AudioCaptureError.captureIncomplete`, which the session surfaces as a toast and menu line like every other capture error, instead of typing the fragment as the dictation. The bound is an absolute gap, not a share of the recording (a first draft used 50%, which would have passed a 5 min dictation missing 2.5 min). The gap is counted from the first buffer, not from the start call (2026-10-23): the engine's own start measured 0.91 s on a loaded machine with AirPods, with nothing lost, which would have put a healthy recording within 0.1 s of the bound. Start-up latency is not missing audio; a short tap passes, and `.noAudioCaptured` already covers an empty one. The `Captured ...` log line reports the start-up and the gap separately, so a device-change recording on device shows what a successful restart costs. Measured on device (2026-10-23): a 59 s dictation that switched from AirPods (24 kHz) to the built-in microphone (48 kHz) part-way logged `startup 0.30 s, gap 0.48 s`, the recording ran to release, and the typed text spanned the switch. A successful restart costs about half the bound.
4. **Fail fast, keep what was heard** (decided 2026-10-23). A watchdog in `AudioCaptureManager` checks the same gap every `Constants.captureWatchdogIntervalSeconds` (1 s) during the recording and, past the bound, calls `onCaptureGapExceeded`; the session ends the recording through `handleDeactivate`, the key-release path, so the user learns within about two seconds instead of at release. Before the first buffer there is no gap to measure, so the watchdog instead ends a recording whose engine has not delivered anything within `Constants.captureStartTimeoutSeconds` (3 s). On the error the session finishes the stream and types the text decoded before the loss, then shows a specific toast ("Recording cut short: the audio device changed or stopped part-way. River typed what it heard; dictate the rest again."). The bound is deliberately tight; a dictation cut short by a false positive is accepted over one that runs on with missing audio, and the threshold is tuned only against measured false positives.

## Tests

- `AudioCaptureManager.convert` joins a 24 kHz run and a 48 kHz run into one continuous 16 kHz stream of the right length, with its energy; `formatRuns` groups consecutive buffers by format.
- The gap check, with an injected clock: 1.5 s of audio for a 14 s recording throws; 150 s of audio for a 300 s recording throws; 1 s of audio for a 1.2 s recording returns; a 0.9 s tap with 0.1 s of audio passes. `captureGapExceeded` is false while idle, during a slow start, and while audio keeps up, and true once it falls behind. A 2 s start followed by audio that keeps up does not trip the watchdog; an engine that never delivers a buffer trips it at the start timeout.
- The watchdog, with a short injected interval, calls `onCaptureGapExceeded` once the audio falls behind, and the session's wiring ends the recording through the deactivate path and surfaces `.audioCapture`.
- `.captureIncomplete` maps to its own toast, distinct from the no-microphone one.
- The device-change handler is live after `startEngine` and inert after `stopEngine`, asserted by calling `handleDeviceChange` directly under `skipEngineForTesting` (superseded the notification test on 2026-10-26).
- The restart itself needs a device and is checked on device only. Since 2026-10-26 a Bluetooth default input no longer restarts anything: with AirPods connected the first recording logs `Default input <private> (device N) is Bluetooth; capturing from the built-in microphone` and `Capture unit started on <private> (device M) at 48000 Hz`, and its buffers track its wall time. A restart is exercised by unplugging a wired microphone mid-recording, which logs `Audio devices changed; moving capture to ...`.

## On-device verification

Smoke-tested by the maintainer on 2026-10-22 on `fix/device-switch` (MacBook Air, AirPods Pro):

- A: AirPods connected and set as default input, first recording after launch. The dictation landed in full; no fragment, no silent no-op.
- B: built-in microphone, AirPods disconnected. Unchanged from before the fix.
- Also observed: dictating on the built-in microphone with the AirPods still connected works.

The `engine restarted` log line was not captured: info-level `audioLogger` output is not persisted for `log show`, so only the behaviour was verified.

## Field result (2026-10-27 – 2026-10-28)

With a log stream open on the installed PR #76 build, 4 of 16 recordings were cut short, all during hours of heavy `swift build` and `swift test` runs; none of the 6 after them were, up to 176 s long. After each `Capture gap exceeded` line, `Capture unit stopped` followed 1.8 s and 2.6 s later, where the two normally land together: the main actor was stalled, so the watchdog likely counted buffers still queued for it as a gap. The toast also names a cause the code did not observe ("The audio device changed or stopped part-way"), and says River typed what it heard even when streaming is off and nothing was typed. Counting the gap on the audio clock and rewording the toast were deferred by the maintainer on 2026-10-28 (Open items in [_index.md](_index.md)).

## Related

- [../architecture/river-pipeline.md](../architecture/river-pipeline.md) — "Device changes mid-recording"
- [../architecture/capabilities.md](../architecture/capabilities.md) — `MicrophoneCapability` owns the engine
- [0023_silence-decoding-hardening.md](0023_silence-decoding-hardening.md) — the trim that turned the 1.5 s of silence into a quiet no-op
