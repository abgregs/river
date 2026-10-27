# Keep the microphone ready, so the first word is never clipped (0033)

**Status: in progress.** Planned 2026-10-21 as a local draft. The capture path (decision 4, the HAL unit) landed in PR #76 on 2026-10-26 and was smoke-tested on device; ready mode, the pre-roll, the switch and the toggle land in `feat/warm-mic`. The on-device acceptance criteria (AC 1, 7, 8) are recorded here when they are run.

## Problem

Capture begins after the key press. Measured on the HAL unit (PR #76, 2026-10-26): 0.07–0.09 s from a warm start and 0.19–0.21 s on the first recording after idle, plus a main-actor stall of about 0.2 s seen on the first activation after idle. Under the previous `AVAudioEngine` path the first recording of a launch took about 0.4 s ([0023](0023_silence-decoding-hardening.md), "Quick taps"). `MicrophoneCapability.startEngine` opens the capture unit on every press, so anything said before its first buffer is lost. A word spoken the instant the key goes down loses its onset (a quick "hi" can decode as "Bye"). The 0.2.0 and 0.2.1 CHANGELOG sections list this as a known issue.

The trim and padding changes in [0023](0023_silence-decoding-hardening.md) recovered short dictations whose audio *was* captured (12 of 30 to 27 of 30). They cannot recover audio that was never recorded.

## Decisions

1. **The microphone is ready by default.** When the app is idle and able to dictate, the capture unit runs and keeps the most recent audio in memory. A press starts the recording from that audio, so it begins *before* the press.
2. **The pre-roll is 0.5 s** (`Constants.preRollSeconds`). It covers the measured start delay (up to about 0.4 s on a cold first activation) with margin. It matches the trim: `silenceTrimLeadSeconds` already keeps only 0.5 s before detected speech, so a longer window adds audio only when speech starts more than 0.5 s before the press. A longer window also costs something. It holds more audio from before the user chose to dictate, such as the end of a remark to someone nearby, and wider margins already produced stray output in 0023. Raise it only if AC 1 shows misses where speech began before the press.
3. **One switch turns it off: "Only use the microphone while dictating"** (`Settings.micOnlyWhileDictating`, default `false`). When on, River behaves exactly as it does today: the unit starts on press and stops after the recording. The switch is named for what the user controls (when the mic is open), not for how the app works inside.
4. **Bluetooth headsets keep their audio quality: River captures from the built-in microphone instead.** When the default input is a Bluetooth device (transport type Bluetooth or Bluetooth LE), River captures from the built-in microphone, and the headset is never asked for input, so it never drops to call mode (HFP) and music keeps its quality, idle or dictating. Ready mode runs on this route like any other. Decided 2026-10-26 from the step 0 rerun: a raw HAL output unit pinned to the built-in microphone before it initialises captured 48 kHz audio while connected AirPods stayed at 48 kHz A2DP and the system defaults were untouched (two other paths passed too; see the step 0 results). The 2026-10-22 failure was `AVAudioEngine`'s alone, because its `inputNode` binds the default input before a pin can take effect. The built-in microphone is also the better capture device: a headset in call mode delivers 24 kHz at best. The cost is that someone dictating through AirPods from across the room gets the laptop's microphone; a microphone picker is still out of scope. A device change re-evaluates the selection (see "Which device"). Landed in PR #76.
5. **The mic is ready only while dictation is possible.** The unit runs when *all* of these are true: onboarding is complete (Microphone, Input Monitoring and Accessibility are all granted, by the same `OnboardingGate` rule that closes the permissions window), the model is `.ready`, the switch is off, and the Mac is awake, unlocked and in the active user session. Otherwise it is stopped. During the first-run download and onboarding the mic stays closed, and the indicator does not show before the user can dictate. Microphone alone is not enough: the model download runs alongside onboarding and can finish while Input Monitoring and Accessibility are still being granted, and a cached model (a reinstall) is ready at once.
6. **If ready mode fails, a press falls back to today's path.** If the unit is not running when the key goes down (it failed, it is restarting after a device change, or the Mac just woke), that recording starts the unit on press, as today, and the fallback is logged. This keeps the current path as the recovery path.
7. **No idle timeout.** The mic does not close after some minutes of disuse. The first dictation after a pause is the common case, and a timeout would clip exactly that one.

### What the user is told

- The switch's description: *"When off, the microphone stays ready, so your first word isn't cut off. The microphone indicator stays on while River is open and able to dictate."*
- The README privacy line (permissions step): River keeps the last half second of audio in memory and discards it continuously. Nothing is saved, transcribed or typed until you press the key.
- The `NSMicrophoneUsageDescription` string ("record your voice for on-device transcription") stays accurate and does not change.

## How

### Prerequisite: survive device changes

A long-lived capture unit sees every device change: AirPods connecting, headphones plugged in, the default input switching. Fixes 1 and 2 of [0032](0032_first-recording-device-switch.md) landed first (PR #75, branch `fix/device-switch`):

- `MicrophoneCapability` observed `.AVAudioEngineConfigurationChange`, re-read the input format, reinstalled the tap and restarted the engine. Superseded by the HAL listeners below.
- `AudioCaptureManager.convert` handles runs of buffers with different formats. Still current.

With the HAL unit (below) the notification went away: a HAL unit pinned to one device does not follow the default. The capability instead listens to the default input device (`kAudioHardwarePropertyDefaultInputDevice`), the device list (`kAudioHardwarePropertyDevices`), and the pinned device's nominal sample rate and liveness (`kAudioDevicePropertyNominalSampleRate`, `kAudioDevicePropertyDeviceIsAlive`), re-runs the selection, and re-pins and restarts when the device or its rate changes (landed in PR #76). CoreAudio delivers one hardware event as a burst of 15–19 listener callbacks, so the handler runs once per burst (PR #78). The restart itself is the same shape as 0032's: tear down, pin, read the format, start, and the format-run conversion absorbs the rate change. The capture gap watchdog (0032 fixes 3 and 4) is the backstop for a pinned device that stops delivering.

Fixes 3 and 4 of 0032 (the capture gap and its watchdog) count the gap from the first buffer of the recording. Pre-roll audio seeded from the window is kept out of `capturedSeconds` and out of the first-buffer clock, otherwise a seeded recording would report a negative gap. The gap therefore starts at the first *live* buffer after the press, exactly as in 0032. Pre-roll does not cover unit start-up: it exists only when the unit is already running, and on the fallback path (decision 6) the press still cold-starts the unit and only the first-buffer clock keeps that latency out of the gap.

### `MicrophoneCapability` (owns the capture unit, rule 3)

- **The capture path is a raw HAL output unit** (`kAudioUnitSubType_HALOutput`, input element enabled, output element disabled), with the device set through `kAudioOutputUnitProperty_CurrentDevice` before `AudioUnitInitialize`, a Float32 mono client format, and an input render callback that pulls each buffer with `AudioUnitRender`. It replaced `AVAudioEngine` for every device, not only the Bluetooth case (PR #76): one path to test on device, one restart routine, one format reader, and `AVAudioEngine` had nothing River used beyond the input tap. Rule 3 changed with it: `AudioOutputUnitStart` is the one gated call, in this type. ADR 0001's "second adapter" condition was not triggered, because there is still one capture implementation behind `audioBuffers`. (The alternative, keeping `AVAudioEngine` for non-Bluetooth defaults and adding the HAL unit beside it, was considered and rejected for the duplicate restart logic and the two on-device matrices; it would also have been the second adapter that triggers ADR 0001's revisit. One path for every device confirmed by the maintainer 2026-10-26.)
- The interface the rest of the app sees does not change: `startEngine()`, `stopEngine()`, `audioBuffers` (freshly allocated `AVAudioPCMBuffer`s on the main actor), `inputLevels`. Buffers are wrapped as `AVAudioPCMBuffer` at the callback so the resampler and `convert` keep working.
- Unit lifetime and recording lifetime are separate. `startEngine()` and `stopEngine()` keep their meaning. The unit now simply runs for longer when the app keeps it ready. The capability reports whether the unit is running (`isCapturing`), so the manager can tell a ready unit from one that failed to start.
- Selects the device (see "Which device") and re-selects on a default-input change or when the pinned device dies, restarting the unit on the new device.
- Buffers and levels are published as now. While idle, nothing displays the levels, because the HUD shows the meter only while recording and `AppState` drops levels outside `.recording`. They still cost main-actor work: about 93 buffer hops per second (the HAL unit delivers the device's IO slice, 512 frames at 48 kHz, where the engine delivered ~100 ms buffers) and up to about 14 level emissions per second (`inputLevelPublishInterval`). AC 7 measures this; coalescing slices in the capture unit before the hop is the mitigation if it shows. If it shows, emit levels only during a recording.

### `AudioCaptureManager` (owns the unit's lifetime and the pre-roll)

- `AudioCaptureManager` is the only caller of `startEngine` and `stopEngine`, for recordings and for ready mode alike. `setReady(_:)` records whether the unit should run between recordings: while idle it starts or stops the unit at once; during a recording the change is applied when the recording ends, so a switch flipped mid-recording cannot stop the unit under the recording.
- While the unit runs and no recording is active, it keeps a rolling window of the most recent buffers (`PreRollWindow`). Oldest buffers are dropped once the rest still cover `preRollSeconds`. Since PR #76 a buffer is one HAL IO slice, 512 frames (~10.7 ms at 48 kHz, ~93 per second), where `AVAudioEngine` delivered ~100 ms buffers. The window therefore holds `preRollSeconds` to within one slice, and the oldest-buffer drop runs ~93 times a second; it is amortised O(1) (a head index with periodic compaction), not an array scan.
- `startRecording` seeds the recording with the window when the unit is running. If streaming is on, it also passes the window to `onSamples`, so `DictationStream` sees the pre-roll too. When the unit is not running at the press, it logs the fallback and takes today's path: stop, then start, so a unit that failed to start is rebuilt rather than skipped by `startEngine`'s idempotency guard.
- `stopRecording` ends the recording without stopping the unit in ready mode. The window starts filling again. The 300 ms wait for a first buffer stays and, like the `.noAudioCaptured` error, keys on the first *live* buffer: a recording that received only the seed is still an error, because the pre-roll alone predates the press and is never typed on its own.
- The pre-roll boundary is "the window at the moment the press is handled on the main actor". The main thread is usually idle at a press, so this delay should be small next to a 0.5 s pre-roll, and press timestamps are not needed. The delay has not been measured. AC 8 measures it, and press timestamps are reconsidered only if it is large.

### Which device

- A pure function, `InputDeviceSelection`, takes the default input device's transport type and the built-in microphone's availability, and returns which device to pin: the default input, unless its transport is Bluetooth or Bluetooth LE, in which case the built-in microphone. It is unit tested without CoreAudio. The chosen device is logged by id at each selection (names are redacted, since a Bluetooth name usually carries the owner's name), so a field log shows which microphone a dictation used. Landed in PR #76.
- When there is no built-in microphone (a desktop Mac with only a headset), the default input is used, Bluetooth or not; that machine has no better option.

### Who decides ready or not

- A pure decision type, `MicrophoneReadiness`, takes the setting, whether onboarding is complete, the model state and the system state, and returns whether the unit should be running. Bluetooth is no longer an input: decision 4 is handled by device selection, not by withholding ready mode. It follows the existing Presentation-enum pattern, so it is unit tested without a unit.
- `RiverSession` subscribes to the switch, the Microphone `status` publisher, the model-load state and the system state, computes the answer, and calls `AudioCaptureManager.setReady(_:)`. The switch does not go through the hotkey apply-or-defer path; the manager's own end-of-recording apply is the deferral ([../architecture/river-session.md](../architecture/river-session.md)).
- The system state comes from these notifications, wrapped by `SystemAvailabilityMonitor`:

  | Event | Notification |
  |---|---|
  | Sleep and wake | `NSWorkspace.willSleepNotification`, `NSWorkspace.didWakeNotification` |
  | Screen lock and unlock | `com.apple.screenIsLocked`, `com.apple.screenIsUnlocked` (distributed notifications) |
  | User session inactive and active | `NSWorkspace.sessionDidResignActiveNotification`, `NSWorkspace.sessionDidBecomeActiveNotification` |

- A revoked permission reaches readiness through its capability's `status` publisher; `RiverSession` puts the three statuses through `OnboardingGate.shouldPresent(statuses:)`. That is the only path: `recheck` runs at launch and on the onboarding Refresh, not on a timer.

### Settings UI

- `Settings.micOnlyWhileDictating` is declared once as a `SettingKey<Bool>` (rule 4). The view reads it with `@AppStorage(Settings.micOnlyWhileDictating.name)`.
- The toggle goes in the General section, with the description above.

## Step 0: verify the headset rule on device (go/no-go)

The 2026-09-24 trace showed CoreAudio building a default-device aggregate of the default input *and* the default output when River's input unit was set up. So it was not proven that capturing from the built-in microphone leaves AirPods in high-quality audio while they are the default output. Step 0 ran before the rest of the work; both results are below.

1. Build a throwaway engine that selects the built-in input with AirPods connected and set as the default output. This is [headset-probe.swift](headset-probe.swift): `swiftc -O docs/planning/headset-probe.swift -o /tmp/headset-probe`, then `/tmp/headset-probe builtin 30` (decision 4) and `/tmp/headset-probe default 30` (today's behaviour, as a control).
2. Start it, play music, and read the Bluetooth and CoreAudio log lines (`HFPInputShimDevice`, `GetBestSampleRate`). The probe tails those lines itself, watches the default devices, and polls the output device's nominal sample rate: A2DP holds 44.1 or 48 kHz, HFP drops to 8–24 kHz.
3. Pass: the AirPods stay in A2DP (the probe prints PASS when the output rate never fell below 44.1 kHz and the defaults held). Decision 4 stands as written. Record both runs' summaries here.

If the AirPods still drop to call mode, ready mode does not run while the default input or output is a Bluetooth headset. That route uses the start-on-press path automatically, and decision 4 changes to that rule.

### Result (2026-10-22): FAIL, the conservative rule applies

Run on the maintainer's MacBook Air with AirPods Pro as the default output and input, music playing, System Settings closed.

```
Summary (builtin)
  default output at start:   AirPods Pro [bluetooth, 48000 Hz]
  default input at start:    AirPods Pro [bluetooth, 24000 Hz]
  input node captured at:    48000 Hz, 299 buffers in 30 s (~9 per s)
  lowest output rate seen:   24000 Hz
  default devices changed:   no
```

The input node did capture from the built-in microphone (48 kHz), and the AirPods still fell to the 24 kHz call-mode rate. Pinning the input unit after the input node exists does not keep them in A2DP. The control run (`default` mode) started with the output already at 24 kHz, so call mode persisted after the first probe exited; it is not a usable control and was not repeated. The maintainer chose the conservative rule without further runs. A pin applied before the input unit initialises (raw AUHAL rather than `AVAudioEngine`) was not tried that day.

### Result (2026-10-26): PASS for all three capture paths that never touch the default device

Run on the same MacBook Air, AirPods Pro as the default output (48 kHz) and default input (24 kHz), no music, System Settings closed. Each mode ran 30 s; the output rate was polled every 0.5 s. Room tone only (the probe counts buffers and reads rates; it never looks at content).

```
Summary (auhal)
  HAL unit captured at:      48000 Hz from MacBook Air Microphone, 2807 buffers in 30 s (~93 per s)
  lowest output rate seen:   48000 Hz
  default devices changed:   no

Summary (avcapture)
  captured:                  48000 Hz via AVCaptureSession on MacBook Air Microphone, 2814 buffers in 30 s (~93 per s)
  lowest output rate seen:   48000 Hz
  default devices changed:   no
```

- **Raw HAL output unit** (`kAudioUnitSubType_HALOutput`), device set with `kAudioOutputUnitProperty_CurrentDevice` before `AudioUnitInitialize`: PASS. The unit reads back as the built-in microphone before and after initialise; the default input stays on the AirPods; the AirPods never left 48 kHz.
- **`AVCaptureSession`** with the built-in `AVCaptureDevice` (matched by CoreAudio UID `BuiltInMicrophoneDevice`) and an `AVCaptureAudioDataOutput` asking for Float32 mono: PASS, same numbers.
- **`AudioQueue`** input pinned by UID with `kAudioQueueProperty_CurrentDevice` before `AudioQueueStart`: PASS. 1506 buffers in 30 s (~50 per s at 20 ms each) at 48 kHz from the built-in microphone; lowest output rate 48000 Hz; defaults unchanged. (A first run hung inside `AudioQueueSetProperty` because the probe passed the UID string unretained; the process stuck in an uninterruptible wait and survived `kill -9`. Probe bug, not an AudioQueue finding.)

What this overturned: the 2026-10-22 failure was specific to `AVAudioEngine`, whose `inputNode` binds the system default input (and builds the default in+out aggregate) before a pin can take effect. Any path that chooses the device before CoreAudio opens anything leaves the AirPods alone. Decision 4 could therefore be: while a Bluetooth device is the default input, River captures from the built-in microphone and the headset stays in A2DP, rather than ready mode being withheld on that route. All three passing paths capture at 48 kHz from the same device.

**Decision (2026-10-26, maintainer):** the raw HAL output unit, pinned to the built-in microphone whenever the default input is Bluetooth, replacing `AVAudioEngine` for every device. Smallest surface of the three, and nothing between the device and the callback. Decision 4 and the `MicrophoneCapability` section above were rewritten to match, and the path landed in PR #76.

## Acceptance criteria

1. With the switch off, a word spoken at the instant of the press keeps its onset. On device, at least 9 of 10 instant-start quick taps ("hi", "yes", "stop") transcribe correctly with the switch off, against a recorded baseline with the switch on. The 0023 replay of saved recordings cannot measure this, because the loss happens before capture. This is a live test, and its protocol and results are recorded in this spec.
2. With the switch on, behaviour, logs and test results match today's.
3. With AirPods connected as the default input and output and the switch off, the capture unit runs on the built-in microphone while River is idle and while dictating, the log names the built-in microphone's id as the selected device, music keeps full quality throughout, and the AirPods' input device stays at its idle rate. Disconnecting the AirPods re-selects the default input without a relaunch; reconnecting re-selects the built-in microphone. The dictating half was verified in the PR #76 smoke (2026-10-26); the idle half is verified with ready mode.
4. The microphone indicator is off during first-run download and onboarding, while the Mac is asleep or locked, and with the switch on while idle.
5. A device change while idle (connect or disconnect AirPods, or change the default input) leaves River ready. The next dictation captures normally with no relaunch.
6. When the unit is not running at the press, that dictation still works through the fallback path, and the fallback is logged.
7. Idle cost is measured and recorded: CPU and Activity Monitor energy impact over 10 idle minutes, with the switch off and on.
   Baseline before ready mode (2026-10-26, PR #76 at `6c39c11`, MacBook Air, unit stopped between dictations): 0 % CPU idle; 20–30 % during dictation and 35–40 % at peak, the streaming decoder dominant. The unit delivers 93 buffers/s (512 frames at 48 kHz). Warm start to first buffer 0.07–0.09 s, cold first start after idle 0.19–0.21 s, a same-device rate-change restart 0.13–0.19 s; gap 0.00–0.08 s normal, 0.19–0.40 s with a restart. Same result with the built-in mic as default and with AirPods as default (captured on the built-in mic). The idle figure with the switch on is measured against the 0 % here.
8. The delay from the press to the recording start is measured and recorded on device. A debug log line in the tap callback is read against the existing `State -> recording` line, over the AC 1 taps. If the delay is more than about 50 ms (a tenth of the pre-roll), revisit press timestamps.

## Tests (swift-testing)

**`MicrophoneReadiness`:** each input that must close the mic closes it:
- the switch on;
- onboarding not complete (any of the three permissions not granted);
- the model not ready;
- asleep, locked, or session inactive.

All inputs favourable means ready.

**`PreRollWindow`:** keeps only the last `preRollSeconds` across buffers of varied duration; draining empties it.

**`AudioCaptureManager` pre-roll**, with injected buffers (`publishForTest`, `skipEngineForTesting`) and the injected clock:
- a recording starts with the window's audio;
- seeded audio does not count toward the capture gap;
- a recording that received only the seed, and no live buffer, is `.noAudioCaptured`;
- streaming receives the pre-roll;
- stopping in ready mode leaves the unit running and the window refilling;
- `setReady(false)` during a recording stops the unit only when the recording ends.

**`RiverSession`:**
- with every input favourable the session marks the manager ready after `start()`;
- the switch on, a missing Microphone, Accessibility or Input Monitoring permission, a model that is not ready, or the Mac asleep each turn it off;
- turning the switch on mid-recording takes effect after `handleDeactivate`;
- `stop()` turns it off.

**Settings:** `micOnlyWhileDictating` defaults to `false` and round-trips.

**Device rule** (landed in PR #76): `InputDeviceSelection` is a pure function of the default input's transport type and the built-in microphone's availability: Bluetooth default with a built-in mic selects the built-in mic; a built-in or USB default selects the default; a Bluetooth default with no built-in mic selects the default. The OS behaviour is checked on device only (step 0, AC 3, AC 5).

**Capture unit** (landed in PR #76): the HAL unit is exercised on device, not in CI, behind `skipEngineForTesting` as today. After initialise the capability reads the unit's device back and logs an error if it is not the selected one, guarding the ordering the probe depended on. The device-change handler is live after `startEngine` and inert after `stopEngine`, and runs once per burst of listener callbacks (PR #78).

## Docs to update in the same change

- `docs/architecture/river-pipeline.md`: replace "Engine warmup" with the ready-microphone lifecycle and the pre-roll.
- `docs/architecture/configuration.md`: the settings table gains `micOnlyWhileDictating`.
- `docs/architecture/capabilities.md`: the unit runs between recordings when the app is ready. (Rule 3 and the device selection were updated in PR #76, as were ADR 0001's note and 0032's superseded note.)
- `docs/architecture/river-session.md`: the readiness subscription.
- `docs/conventions/tests.md`: the new seams.
- `README.md`: the privacy line above.
- `CHANGELOG.md`: a Fixed entry under Unreleased for the onset, and an Added entry for the switch. The released sections keep their known-issue lines as written.

## Delivery

Two stacked PRs from `main`, so the capture path lands and is smoke-tested before anything depends on it:

1. `feat/hal-capture`: `MicrophoneCapability` on the HAL unit, `InputDeviceSelection`, HAL listeners replacing the configuration-change notification, rule 3 and docs. Behaviour otherwise as before (unit starts on press). **Landed as PR #76 (2026-10-26)**, smoke-tested on device in five scenarios: the built-in mic; AirPods as default input and output with music; AirPods removed and reinserted mid-dictation; the built-in mic chosen with AirPods connected; a sample-rate change mid-dictation in both directions.
2. `feat/warm-mic`, stacked on `fix/device-change-fanout` (PR #78): ready mode, pre-roll, `MicrophoneReadiness`, the setting, the toggle. AC 1 and AC 7/8 are measured on device once the current installed build has finished its field-log run, and recorded here.

The capture-gap watchdog revisit (a separate, untracked draft) is independent. This spec keeps 0032's gap semantics unchanged: the gap starts at the first live buffer of the recording.

## Out of scope

- A microphone picker in Settings.
- Keeping audio after the key release, and aligning clip boundaries to event and audio timestamps. Revisit both if the live test in AC 1 shows loss at the end of quick taps.
- Any minimum hold length, or discarding short presses.
- Idle-cost mitigation (coalescing buffer hops, emitting levels only while recording) until AC 7 shows a cost.
