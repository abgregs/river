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

1. **Survive a configuration change.** `MicrophoneCapability` observes `.AVAudioEngineConfigurationChange` for its engine. On the change it re-reads the input format, reinstalls the tap, and restarts the engine in place, logging the new format. `AVAudioEngine.start` stays in that one capability (AGENTS.md rule 3). The observer is installed with the engine and removed by `stopEngine`, so a change can neither be missed during a recording nor restart an engine that was deliberately stopped.
2. **Convert mixed formats.** `AudioCaptureManager.convert` assumed every buffer shared the first buffer's format. After a restart the buffers change rate (24 kHz → 48 kHz) and would be resampled wrongly. `convert(_:toSampleRate:)` now splits the recording into runs of same-format buffers (`formatRuns`), converts each run with its own converter, and joins them.
3. **Never fail silently.** If the restart failed and the captured audio covers less than half of a recording longer than a second (`Constants.captureCoverageMinimumRatio`, `captureCoverageCheckedAfterSeconds`), `stopRecording` throws `AudioCaptureError.captureIncomplete`, which the session surfaces as a toast and menu line like every other capture error, instead of typing the fragment as the dictation. Short recordings are exempt: the engine's own warmup is a large share of them, and `.noAudioCaptured` already covers an empty one.

## Tests

- `AudioCaptureManager.convert` joins a 24 kHz run and a 48 kHz run into one continuous 16 kHz stream of the right length, with its energy; `formatRuns` groups consecutive buffers by format.
- The coverage check, with an injected clock: 1.5 s of audio for a 14 s recording throws; 1 s of audio for a 1.2 s recording returns; a 0.9 s tap with 0.1 s of audio is exempt.
- The configuration-change observer is live after `startEngine` and gone after `stopEngine`, asserted by posting the notification under `skipEngineForTesting`.
- The restart itself needs a device and is checked on device only: with AirPods connected, relaunch, dictate twice, and read the `audio` log lines. The first recording should log `Audio configuration changed; engine restarted with input format 48000 Hz`, and its buffers should track its wall time.

## On-device verification

Pending the maintainer's smoke on `fix/device-switch`.

## Related

- [../architecture/river-pipeline.md](../architecture/river-pipeline.md) — "Device changes mid-recording"
- [../architecture/capabilities.md](../architecture/capabilities.md) — `MicrophoneCapability` owns the engine
- [0023_silence-decoding-hardening.md](0023_silence-decoding-hardening.md) — the trim that turned the 1.5 s of silence into a quiet no-op
