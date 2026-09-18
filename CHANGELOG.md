# Changelog

All notable changes to River are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
(see [docs/conventions/versioning-and-releases.md](docs/conventions/versioning-and-releases.md)).

<!-- Link definitions live above the first version header on purpose: the release
workflow extracts a section as everything between its header and the next one, and
Sparkle renders those notes literally in a <pre>, where stray link definitions would
show as raw text. -->

[Unreleased]: https://github.com/abgregs/river/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/abgregs/river/releases/tag/v0.1.0

## [Unreleased]

## [0.1.0] - 2026-09-18

First public release — a macOS menu bar dictation app with fully on-device transcription.

### Added
- Dictation cycle: hold (or tap) an activation key, speak, and the text is typed in at your cursor.
- Three activation modes — Hold (push-to-talk), Single Tap, and Double Tap.
- Configurable activation key with ten modifier-key options (default: Right Option).
- On-device transcription via WhisperKit (`small.en`, ~240 MB, downloaded on first launch); no audio or text ever leaves your Mac.
- Keystroke-injection text insertion — your clipboard is never read or written.
- A guard that skips non-editable targets, so dictation can't fire text into the wrong place.
- Live settings: activation key and mode changes apply instantly, no restart.
- Launch at login.
- Guided onboarding for the Microphone, Input Monitoring, and Accessibility permissions.
- Menu bar status that tracks the cycle (Ready → Recording → Processing) and surfaces errors, using River's own slat glyph.
- A recording indicator: three strands that follow your voice while listening, and carry a flowing crest of ink while transcribing. It never takes focus, so the text still lands where you were typing.
- Transient error toasts with a recovery hint, and a model-loading label during first-launch warm-up.
- Cancel an in-flight recording with the fn key, or from the menu.
- "Copy Last Transcription" in the menu, for when a paste goes somewhere unexpected.
- Optional sound cues on recording start and stop — **off by default**.
- A model picker with four curated WhisperKit models.
- Silence trimming and no-speech gating, so an accidental activation is less likely to paste invented text.
- In-app update checks via Sparkle.
- Signed and notarized `.dmg`, plus a Homebrew cask (`brew install --cask abgregs/river/river`).

### Known issues

- **Trailing invented text.** After real speech, the model can append a plausible sentence that you never said — most often when a dictation ends with silence or breath. Silence trimming and no-speech gating reduce it; they do not eliminate it. Check what lands before sending it.
- **Switching models mid-download.** A model still downloading in the background can make a cached model look unavailable, and a failed load needs a relaunch to retry.
- **Permissions may need a Refresh.** After granting a permission in System Settings, onboarding does not always notice on its own; press Refresh, and on a first launch after an update you may need to relaunch River.
- **Apple Silicon and macOS 14+ only.** There is no Intel build.
- **English only.** The shipped models are the `.en` family.
