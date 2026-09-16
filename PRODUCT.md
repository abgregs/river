# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS 14+ app, Apple Silicon only, built with SwiftUI and AppKit. Not web, iOS, or Android; where this record's schema expects one of those, read every platform instruction as the macOS equivalent. Distributed outside the App Store as a signed, notarized DMG and a Homebrew cask, not sandboxed (see `docs/architecture/distribution.md`).

## Users

**Anyone who types on a Mac.** The framing is deliberately broad: writers, students, professionals, developers, anyone who thinks faster than they type. The identity stays approachable rather than assuming a technical audience, even though the current install path is technical.

The job: you are already in some app, mid-thought, with the cursor where the words belong. You hold or tap one key, speak, and the text lands there. Nothing to open, nothing to switch to, nothing to paste.

## Product Purpose

Dictation that follows you wherever you go. River is a menu bar utility that turns speech into text at the cursor, in any app that accepts typing, with transcription running entirely on the user's Mac.

Success is that the user stops thinking about the tool: activation is one key, the text arrives where they were already looking, and nothing about the experience suggests a service, an account, or a network.

## Positioning

Three things together, which a neighboring product cannot truthfully copy without becoming this one:

- **Fully local.** Transcription runs on-device via WhisperKit. No audio or text leaves the machine, so there is no latency floor set by a network, no usage cost, and no trust question about recordings.
- **Free and open source.** MIT, no paid tier, no license key, no subscription, in a category where the polished competitors are paid.
- **Everywhere you can type.** Not a voice mode inside one editor: one hotkey, any app, text injected as keystrokes so the clipboard is never touched.

## Operating Context

- Lives in the menu bar; the user's attention is in whatever app they are typing into, not in River.
- The whole cycle is one activation key, configurable across ten modifier keys, in Hold, Single Tap, or Double Tap mode.
- macOS gates the app on three permissions: Microphone, Input Monitoring, and Accessibility. First run is a permissions walkthrough, and permission state is an ongoing part of the experience, not a one-time setup step.
- First launch downloads a speech model, roughly 140 MB to 1.4 GB depending on the choice, into Application Support. Every launch and dictation after that is offline. Large models take minutes to prepare on first load.
- Updates arrive in-app via Sparkle; Homebrew defers to it.

## Capabilities and Constraints

**Today:** activation-to-text cycle in three modes; ten configurable activation keys; keystroke injection with a non-editable-target guard; a floating recording indicator with live input level and transient error toasts; optional sound cues; cancel-recording; copy-last-transcript recovery; a model picker with load-state feedback; guided onboarding and a Permissions menu item; launch at login; in-app auto-update.

**Constraints:** macOS 14+, Apple Silicon only. English-only models today. Transcription is paste-at-the-end, not streaming. The transcription model is replaceable by design, so nothing user-facing should name or depend on a specific model or vendor.

**Scope (clarified 2026-09-16):** River is **dictation at the cursor**, and that is what the product, its audience framing, and its identity serve. Streaming insertion and text expansion refine that one job. Broader voice-to-text uses — voice notes, meeting capture, transcribing existing audio — are not ruled out forever, but they are not what this product is, and no design or identity decision should be made to accommodate them.

**Open decisions:** whether a sharper standalone settings window replaces or supplements the menu bar dropdown, in the spirit of Raycast's panel, is undecided and deliberately not foreclosed; continuous streaming insertion and text expansion are specced but unimplemented.

## Brand Commitments

**Name:** River. Text flows in and follows you from app to app.

**Permanent commitments, confirmed 2026-09-16 and not to be broken by future work:**

- **Fully on-device, always.** No cloud transcription, not even as an opt-in setting, and no bring-your-own-API-key path.
- **Free and open source.** No paid tier, subscription, or license key.
- **No account, no telemetry.** No sign-in, analytics, or crash reporting that phones home.

**Explicitly not a commitment:** menu-bar-only. A larger, sharper settings surface may be added later.

## Evidence on Hand

- Working, smoke-verified application on `main`; no public release has been cut yet, so there are no users, download counts, reviews, testimonials, or press. Future work must not imply any.
- Documentation set under `docs/` covering architecture, conventions, requirements, planning, and decisions; `docs/design/direction.md` records an identity brief written before this record.
- No icon, logo, custom glyphs, or brand assets of any kind exist yet. The app currently ships the generic macOS placeholder icon and stock SF Symbols.
- No screenshots are committed; the README references `assets/` images that do not exist yet.

## Product Principles

1. **The cursor is the product.** Text arrives where the user was already working. Any surface that pulls focus, steals the caret, or asks the user to come to River has failed.
2. **Local is the whole point.** On-device is not a feature flag or a privacy claim in marketing copy; it is the reason the product exists and it constrains every future capability.
3. **Model-neutral.** The speech model is an implementation detail that will change. Nothing in the name, interface, or copy ties the product to one.
4. **Permissions are the app's job, not the user's.** The app determines its own permission state and asks for the minimum; it never makes the user perform its bookkeeping.
5. **Honest about failure.** A dictation that could not be delivered says so, in the moment, where the user is looking. Silence is the one unacceptable outcome.

## Accessibility & Inclusion

Dictation is an accessibility tool for some users even though the framing is broad, so a typing-free path through the core cycle matters. Onboarding, the permissions flow, and the recording indicator must not depend on color alone or on motion the user cannot disable; macOS Reduce Motion and Increase Contrast are honored. No formal standard has been adopted as a requirement.
