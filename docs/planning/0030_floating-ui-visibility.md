# Planning: Floating UI Visibility (roadmap 0030)

A bug record. Reported by the maintainer on 2026-10-08 and diagnosed the same day. The fix is on branch `fix/floating-ui-visibility`.

## Problem

The maintainer reported two symptoms. They are grouped here because both are about the floating UI, meaning the recording indicator and the transcript panel:

1. **The floating UI stops appearing.** Sometimes nothing appears when recording starts: no indicator and no panel. Dictation still works, and text still arrives at the cursor. Quitting and relaunching River usually brings the UI back.
2. **It goes missing on other Spaces.** The maintainer swipes between Spaces on the trackpad: one desktop, plus several full-screen apps. A recording that started with the UI visible usually keeps it as the maintainer swipes. But a recording started on one of the other Spaces sometimes shows nothing. Swiping back to the first desktop, the one River starts on at login, sometimes shows the UI there.

## Cause

**Closing a full-screen Space can take River's panels off every Space, and nothing puts them back.**

Both panels are long-lived `NonActivatingPanel`s. Their collection behavior is `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, and the coordinators build each panel once at launch. When a panel is first ordered in, the window server adds it to every current Space. It also adds the panel to each full-screen Space created later. A panel that is ordered out keeps that membership.

The WindowServer log (`com.apple.SkyLight`, read with `log show --debug`) shows the failure on 2026-10-08, during the River session that ran from 22:08 to 22:46:

- **22:08:09:** both panels (`19f5` and `19f6`) are ordered in for the first time and join all seven Spaces.
- **22:13:50:** VS Code goes full screen. The window server creates managed Space 177 with backing Space 178, and both panels join 178.
- **22:21:56:** the full-screen VS Code window closes, and Spaces 177–179 and 182 are destroyed. At 22:21:57, `BatchReassociateWindowsToSpace` removes both panels from all eight of their Spaces, including the login desktop (3), and adds them to none. River was idle at that moment, so the panels were already ordered out.
- **22:23 to 22:46:** River logs `order window: 19f5 op: 1` for six recordings, so the coordinators did order the panels in. No `joined space` line ever follows. Ordering a panel in does not rebuild membership it once had, so the panels showed on no Space.
- **22:46:16:** the maintainer relaunches. The new panels join all seven Spaces, as they did at 22:08.

That record matches symptom 1 exactly. Symptom 2 fits the same failure, where the reassociation leaves a panel on fewer Spaces than intended. The logs for earlier days are no longer retained, so this version is inferred from symptom 1, not observed.

### Ruled out

Each of these was checked against the same session, a read-only probe of River's live windows, or a harness that stood up the real coordinator:

- **The coordinators failing to order the panels in.** AppKit logs an order-in at every recording.
- **The hosted SwiftUI content sticking at opacity 0.** A shown panel rendered at full alpha in the harness, both on the current Space and after each of the maintainer's own Space changes.
- **Off-screen placement.** There is one display, and the frames match the layout arithmetic.
- **Membership on a never-closed Space.** River's panels stayed on all seven Spaces through 30 minutes of the maintainer's swiping.

## Fix

After a panel that has been on screen fades out and is ordered out, each coordinator closes it and builds a new one. The new panel is never shown until the next recording. So every recording orders in a fresh panel, which joins every current Space just as a relaunch does. A panel that was never shown is kept.

Building the panel ahead of time preserves why the coordinators build at launch: the first recording fades in, not appearing fully drawn. Building one is a single `NSPanel` plus its `NSHostingView` per dictation.

- **Regression test:** `RecordingIndicatorCoordinatorTests` drives the real coordinator against real, transparent panels. It checks that a shown panel is replaced after the fade, and that a panel never shown is kept.
- **What the test can't stage:** the window server's reassociation itself, so it checks the remedy, not the trigger.
- **`TranscriptPanelCoordinator`:** has the same change and no test of its own, because its visibility needs streamed text that only the session publishes.

## Not fixed here

- **The level is not what the code intends.** `isFloatingPanel = true` runs after `level = .statusBar`, and that property resets the level to `.floating`. Both panels therefore run at level 3, not 25, as the live windows confirm. Nothing ties this to the symptoms above, so the level is unchanged. Raising it changes how the panels stack against other apps' panels and full-screen content, which needs its own on-device check.
- **A Space that closes during a recording.** If a full-screen Space closes while a panel is on screen, the panel can still disappear until that recording ends. The next recording gets a new panel.

## Verification

- **Root cause:** the WindowServer and AppKit log sequence above.
- **Remedy:** every replacement panel joined all seven Spaces when first ordered in, and its content rendered.
- **Tests:** `swift test` passes, with 307 tests and the env-gated suites skipped, and `make verify` passes.
- **On device, not verified:** closing a full-screen app while River is idle, then recording on each Space. The first recording's fade-in on a freshly built panel is also unchecked.

## Related

- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md): the panel's design and acceptance criterion 4, which requires the panel over full-screen apps and on every Space.
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md): the state seam both coordinators observe.
