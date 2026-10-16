import Foundation

enum Constants {
    static let bundleIdentifier = "com.river.app"
    static let loggingSubsystem = "com.river.app"

    // Subfolder under ~/Library/Application Support holding the downloaded
    // WhisperKit model. Application Support (not WhisperKit's ~/Documents
    // default) keeps model downloads from tripping the Documents-folder TCC
    // prompt. See planning/0010_relocate-model-cache.md.
    static let modelCacheFolderName = "River"

    // Right Option — universal on all Mac keyboards (including MacBook and
    // Magic Keyboard) and rarely pressed during typing, so Hold mode doesn't
    // accidentally trigger on capitalization or shortcuts. `@AppStorage` does
    // not bind `CGKeyCode` (a `UInt32` typealias), so the canonical type is
    // `Int`; cast at use sites.
    static let defaultActivationKeyCode: Int = 61

    // Default activation mode. Hold is the safe default — it fires on a held key
    // and works on every supported key (the tap modes add ~50–100 ms latency and
    // are the only ones reliable on Caps Lock). See requirements/activation-key-and-mode.md.
    static let defaultActivationMode: ActivationMode = .hold

    // Cancel gesture (planning 0017). Tapping this modifier key while recording
    // discards the in-flight recording — no transcription, no paste. It MUST be a
    // *modifier* keycode, because the event tap observes `.flagsChanged` only and
    // never `keyDown` (the 0006 least-privilege posture — see
    // planning/0006_runtime-security-hardening.md); Escape (a keyDown) is therefore
    // off-limits without widening the tap. fn/Globe (63) is universal on Apple
    // keyboards, is rarely chorded during dictation (unlike Command/Control/Shift,
    // which would false-cancel on every shortcut), and is distinct from the default
    // activation key. The menu-bar "Cancel Recording" item is the always-available
    // discoverable fallback. Internal tunable, not a user setting (AGENTS.md rule
    // #5). If it ever equals the watched activation key the gesture disables itself
    // (the menu item still works). Verify fn delivers a `.flagsChanged` with keycode
    // 63 on-device — the Globe key is special-cased on some keyboards.
    static let cancelKeyCode: Int = 63

    // Double-tap detection window. Two complete taps within this many milliseconds
    // start a recording. Deliberately an internal tunable, NOT a user setting:
    // exposing a slider is friction for a value the user shouldn't have to reason
    // about. 400 ms matches the platform's double-click feel.
    static let doubleTapWindowMs: Int = 400

    // WhisperKit model identifier. `small.en` is the default because the custom
    // dictionary (prompt-token biasing) is unreliable on smaller models: `base.en`
    // degenerates to empty output when given a prompt (verified via the A/B eval
    // harness — see requirements/custom-dictionary.md). `small.en` (~490 MB) handles
    // prompts robustly and is more accurate, at some cost in speed/memory. The model
    // picker (planning 0021) lets speed-focused users drop back to `base.en`; this is
    // the default the `Settings.selectedModel` key sources.
    static let defaultModel: String = "openai_whisper-small.en"

    // PROVISIONAL curated list for the model picker (planning 0021). The final list
    // and default are decided by 0022's per-model scorecards, which don't exist yet —
    // these four are placeholders: the two known-good English models plus two stronger
    // candidates that have never been evaluated here. Names are the exact
    // `argmaxinc/whisperkit-coreml` repo folders WhisperKit downloads (verified against
    // WhisperKit 0.18's model tables). Sizes are each folder's total in that repo, which
    // matches the on-disk footprint (measured 2026-09-29). Each
    // entry must earn its place via a 0022 scorecard before this list is finalized.
    static let curatedModels: [ModelOption] = [
        ModelOption(
            name: "openai_whisper-base.en",
            label: "Base (English)",
            hint: "Fastest, smallest (~150 MB). Lower accuracy."
        ),
        ModelOption(
            name: defaultModel,   // openai_whisper-small.en
            label: "Small (English)",
            hint: "Balanced speed and accuracy (~490 MB). Current default."
        ),
        ModelOption(
            name: "distil-whisper_distil-large-v3",
            label: "Distil Large v3",
            hint: "High accuracy, distilled for speed (~1.5 GB). The first load can take a few minutes."
        ),
        ModelOption(
            name: "openai_whisper-large-v3-v20240930_turbo",
            label: "Large v3 Turbo",
            hint: "Most accurate, turbo decoding (~1.6 GB). Slowest to load; the first load can take a few minutes."
        ),
    ]

    // Seed for the user-editable custom dictionary. Empty by default; the user
    // curates terms in Settings (M8). A curated starter list could be added here
    // later. See requirements/custom-dictionary.md.
    static let defaultDictionaryTerms: [String] = []

    // Max UTF-16 code units per synthesized keystroke event. Text insertion
    // injects the transcription as Unicode key events (`keyboardSetUnicodeString`),
    // chunked because that call is unreliable past ~20 units in some apps. Internal
    // tunable, validated on-device. See planning/0011_keystroke-injection.md.
    static let keystrokeChunkUnits: Int = 20
    // Pause between keystroke chunks, so the target reads the transcript a few chunks
    // at a time instead of in one burst. Posted back to back, a long transcript reached
    // Claude Code's TUI as reads of 800+ characters, which it treats as unmarked pastes:
    // it showed `[Pasted text #N]` placeholders and dropped about 2 KB of a 3,000-character
    // insert in 4 of 5 runs. 1 ms between chunks was enough in every run; 4 ms leaves
    // room for a busy target, and adds about 0.2 s per 1,000 characters (planning 0031).
    static let keystrokeChunkGapSeconds: Double = 0.004

    // Silence-trim energy gate: a 16 kHz window whose RMS is below this (linear
    // amplitude, not dBFS) is treated as silence and dropped from the ends of the
    // recording. Internal tunable, not a setting — the user shouldn't reason about
    // dBFS (AGENTS.md rule #5). First-pass value: an on-device probe with
    // ad-hoc clips showed real room tone peaks ABOVE it (~0.02 RMS windows), so
    // the trim only catches near-digital silence; realistic near-silence is
    // handled by `TranscriptionManager.isNonSpeechAnnotation` instead. Tune
    // against the 0022 silence corpus once it's recorded.
    static let silenceTrimEnergyThreshold: Float = 0.01
    // Quiet recordings get a lower gate: the cut sits `silenceTrimPeakRatio` below the
    // recording's loudest window, never above `silenceTrimEnergyThreshold` and never below
    // `silenceTrimFloor`. A fixed -40 dBFS gate discarded whole quiet dictations: quiet
    // talking on a built-in mic was never transcribed (maintainer's smoke, 2026-09-24).
    // Normal speech peaks near -24 dBFS or louder, where the relative cut reaches the
    // fixed gate, so its trailing trim is unchanged (planning 0023's tail finding).
    static let silenceTrimPeakRatio: Float = 0.18      // about 15 dB below the peak window
    static let silenceTrimFloor: Float = 0.0032        // about -50 dBFS: quieter is never speech

    // Audio kept around detected speech. The lead-in is the context Whisper needs to hear a
    // word's soft start: with 0.1 s, quick taps reached it clipped mid-word and decoded to
    // nothing (maintainer's smoke, 2026-09-26). The tail stays short, since room tone after
    // speech is what Whisper turns into invented text (planning 0023).
    static let silenceTrimLeadSeconds: Double = 0.5
    static let silenceTrimTailSeconds: Double = 0.2

    // Whisper returns nothing for a word shorter than about a second unless silence
    // surrounds it, so a clip under `shortClipSeconds` is decoded with `shortClipPadSeconds`
    // of silence on each side. Longer clips are decoded as captured: padding them hurt
    // some real recordings in the replay (maintainer's smoke, 2026-09-26).
    static let shortClipSeconds: Double = 1.2
    static let shortClipPadSeconds: Double = 0.5

    // Streaming (0025 prototype; values from docs/planning/drafts/0025-streaming-review.md).
    // A pause of `streamingPauseSeconds` after `streamingMinVoicedSeconds` of speech cuts a
    // segment: 0.7 s cut thinking pauses into fragments, 1.0 s read better once joined. The
    // voiced minimum is also the pre-decode gate (distil decodes noise as "Thank you."). A
    // speaker who never pauses is cut every `streamingMaxSegmentSeconds`, at the quietest
    // 100 ms in the last `streamingForcedCutSearchSeconds`: arbitrary cut instants cost 3–6 %
    // WER, the quietest point none. Each segment is decoded with `streamingOverlapSeconds`
    // of the previous one in front so the join can be aligned (3 s was no better than 2).
    static let streamingPauseSeconds: Double = 1.0
    static let streamingMinVoicedSeconds: Double = 1.5
    static let streamingMaxSegmentSeconds: Double = 10
    static let streamingForcedCutSearchSeconds: Double = 2
    static let streamingOverlapSeconds: Double = 2
    // The tail left at release after earlier segments is decoded only if it holds this much
    // speech; less is a breath or room tone. A first guess: a 0.3 s fragment of real speech
    // decoded to "I want" in the probe, so this sits just below it.
    static let streamingTailMinVoicedSeconds: Double = 0.25
    // Between cuts, the phrase still being spoken is decoded every
    // `streamingProvisionalIntervalSeconds` of new audio, for the panel only, once it holds
    // `streamingProvisionalMinVoicedSeconds` of speech (shorter fragments decode to partial
    // words). First guesses, to tune on device.
    static let streamingProvisionalIntervalSeconds: Double = 0.5
    static let streamingProvisionalMinVoicedSeconds: Double = 1.0

    // Decoding thresholds pinned to upstream Whisper defaults (planning 0023): they
    // drive the temperature fallback for low-confidence segments and are *meant* to
    // gate silent audio to empty output — but an on-device probe showed they don't
    // reliably suppress non-speech ("[BLANK_AUDIO]" still decodes from real room
    // tone); `isNonSpeechAnnotation` is the layer that actually stops the paste.
    // WhisperKit 0.18 already defaults to these, but we set them explicitly so the
    // gate can't silently regress if an upstream default changes. Internal tunables,
    // not settings.
    static let noSpeechThreshold: Float = 0.6
    static let logProbThreshold: Float = -1.0
    static let compressionRatioThreshold: Float = 2.4
    // Temperature 0 with 5 fallback increments of 0.2 reaches 1.0 — the upstream
    // Whisper schedule (temperatures 0, 0.2, 0.4, 0.6, 0.8, 1.0).
    static let decodingTemperature: Float = 0.0
    static let decodingTemperatureIncrementOnFallback: Float = 0.2
    static let decodingTemperatureFallbackCount: Int = 5

    // Recording-indicator HUD (planning 0002/0018/0020). These are internal
    // tunables, NOT settings: the HUD has no user-facing configuration (AGENTS.md
    // rule #5), so its timing, layout, and thresholds live here.

    // Fade in/out duration for the HUD panel. The panel is ordered out only after
    // this outlives the return to `.idle`, so the fade animation completes on screen
    // before the window is removed (planning 0002 acceptance criterion 2).
    static let hudFadeSeconds: Double = 0.22
    // Gap between the mark's panel and the bottom of the active screen's visible frame (the
    // Dock's top edge, or the screen's bottom when the Dock hides): about the gap between
    // Dock icons, so the mark sits just above the Dock like one more tile.
    static let hudBottomMargin: Double = 8

    // River's mark: three stones inspired by a bold lowercase r that morph into level bars
    // (docs/design/stones-identity.md). Every number was tuned on the study page
    // (docs/design/studies/stones-motion.html) and is ported as is. The shapes themselves live in
    // `StoneMark`, in their own design units.

    // The mark is drawn 30 pt tall, centered in a 34 pt square, so it keeps 9 pt of room above
    // and below inside the panel (filling the square read as crammed, maintainer 2026-10-14).
    // The panel is a 48 pt square, a little smaller than a Dock icon at the default tile size,
    // and never changes size.
    static let indicatorMarkSize: Double = 34
    static let indicatorMarkHeight: Double = 30
    static let indicatorPanelHorizontalPadding: Double = 7
    static let indicatorPanelVerticalPadding: Double = 7
    static let indicatorPanelWidth: Double = indicatorMarkSize + 2 * indicatorPanelHorizontalPadding
    static let indicatorPanelHeight: Double = indicatorMarkSize + 2 * indicatorPanelVerticalPadding
    // About a Dock icon's corner at this size, so the mark reads as one more tile.
    static let indicatorPanelCornerRadius: Double = 11

    // The HUD surface every floating shape shares, matched to a native dark HUD window
    // (Raycast Notes, measured 2026-10-09): the desktop behind blurred, a tint over it, a light
    // inner hairline that brightens along the top edge, and a dark outer line that holds the
    // edge over light desktops. It follows Light and Dark mode (`Palette.HUD`). Reduce
    // Transparency swaps blur and tint for the tint, opaque. Dark, measured on screen
    // 2026-10-09: over black the ground is #131315 (Raycast's is #151719); over a white page,
    // the lightest ground the blur produces, ink holds 9.65:1 and the accent 7.27:1.
    static let hudDarkTintOpacity: Double = 0.72
    static let hudDarkHairlineOpacity: Double = 0.2
    static let hudDarkHairlineTopOpacity: Double = 0.35
    static let hudDarkOuterLineOpacity: Double = 0.8
    // Light, 2026-10-15: at 0.72 a light panel over a black desktop leaves the deep accent at
    // 2.13:1; 0.88 holds 3:1 with the blur ignored, the worst case. A white hairline only shows
    // as sheen on a light tint, and a black outer line at the dark value would read as a frame.
    // The lines are first values, to tune on device.
    static let hudLightTintOpacity: Double = 0.88
    static let hudLightHairlineOpacity: Double = 0.5
    static let hudLightHairlineTopOpacity: Double = 0.9
    static let hudLightOuterLineOpacity: Double = 0.12
    static let hudHairlineWidth: Double = 1
    static let hudOuterLineWidth: Double = 0.5
    // One soft shadow, drawn outside the edge only: the blur hides whatever lies beneath it.
    static let hudShadowRadius: Double = 18
    static let hudShadowOffset: Double = 8
    static let hudShadowOpacity: Double = 0.3
    // Transparent margin around the HUD content so the far shadow is not clipped by the panel.
    static let hudShadowMargin: Double = 48
    // Enter rises and exit drops by this much over `hudFadeSeconds`; Reduce Motion drops the rise.
    static let hudFadeRise: Double = 6

    // The rounded rectangle holding the toast, loading label, and notice, stacked with the capsule.
    static let hudMessageCornerRadius: Double = 16
    static let hudMessagePadding: Double = 12
    static let hudMessageWidth: Double = 260
    static let hudStackSpacing: Double = 8
    // Space always reserved above the mark for that rectangle, which grows upward from the
    // mark so the Dock never covers it. The panel is this one
    // fixed size whatever it shows, so the capsule's position is arithmetic and a message
    // appearing or leaving can never move it (the shift the maintainer saw on cancel,
    // 2026-09-17, when a notice grew the content inside an already-sized panel).
    static let hudMessageReservedHeight: Double = 140

    // The streaming transcript panel: its own surface, a fixed size, `hudStackSpacing` above
    // the mark's panel. Bare prototype UI; scrolls when the text outgrows it.
    static let transcriptPanelWidth: Double = 440
    static let transcriptPanelHeight: Double = 176
    static let transcriptPanelCornerRadius: Double = 12
    static let transcriptPanelHorizontalPadding: Double = 16
    static let transcriptPanelVerticalPadding: Double = 14
    static let transcriptFontSize: Double = 14

    // Motion. The panel opens on the r and holds it, then each stone morphs into its bar on its
    // own critically damped spring, the three starting a stagger apart, left to right. On
    // release the morph runs back right to left, and the r holds until the panel fades.
    static let markHoldSeconds: Double = 0.35
    static let markStaggerSeconds: Double = 0.04
    // The spring's response: the period it would ring at without damping.
    static let markMorphResponse: Double = 0.24
    // Reduce Motion: no morph; the mark dips out and back while the r and the bars swap.
    static let markFadeThroughSeconds: Double = 0.24
    // The smoothed level Reduce Motion's bars follow.
    static let markLevelAttackRate: Double = 10
    static let markLevelReleaseRate: Double = 5
    // Longest frame interval the engine advances by, so a resumed timeline does not leap.
    static let markMaxFrameInterval: Double = 0.05

    // The bars read loudness in decibels of full scale (dBFS); a linear scale left quiet
    // speech invisible on a built-in mic (maintainer's smoke, 2026-09-24). The floor is the
    // capture trim's floor, so the bars never move for a recording the trim then discards as
    // silence: bars that moved for a dictation River threw away would claim it heard you. Below
    // the floor they hold still at their resting height, so motion always means sound. The
    // ceiling is a full bar. Display only: the bars read `inputLevel`, which the capture path
    // never uses.
    static let markMeterFloorDecibels: Double = 20 * log10(Double(silenceTrimFloor))
    static let markMeterCeilingDecibels: Double = -28
    // Each bar is its own readout: it re-reads the voice on its own clock, at a random interval
    // in this range, at its own gain and a random spread, so the three move out of step.
    static let markBarSampleInterval: ClosedRange<Double> = 0.06...0.11
    static let markBarGains: [Double] = [0.82, 1, 0.9]
    static let markBarSpread: ClosedRange<Double> = 0.85...1.15
    // Bars rise fast and fall slowly, like a level meter (about 0.05 s up, 0.25 s down).
    static let markBarRiseRate: Double = 20
    static let markBarFallRate: Double = 4

    // Menu bar glyphs: the mark in an 18 pt image, 16 pt tall. Ready is the r as a template
    // image the system tints; Listening and Transcribing are one frozen reading of the bars in
    // the accent, an image per menu bar appearance.
    static let menuBarGlyphSize: Double = 18
    static let menuBarMarkHeight: Double = 16
    static let menuBarActiveLevels: [Double] = [0.55, 1, 0.75]

    // App icon: the stones r in ink on a charcoal squircle (maintainer, 2026-10-14), drawn on
    // Apple's 1024 grid where the rounded square occupies 824 of the canvas.
    static let appIconCanvas: Double = 1024
    static let appIconSquircleInset: Double = 100
    static let appIconCornerRadius: Double = 185.4
    // The r's height as a fraction of the squircle's.
    static let appIconMarkFraction: Double = 0.56
    static let appIconFileName = "River.icns"

    // How long an error toast stays on the HUD before auto-dismissing (planning
    // 0018 acceptance criterion 1). Long enough to read a headline + hint, short
    // enough to "get out of the way."
    static let errorToastDurationSeconds: Double = 4.0

    // nspasteboard.org marker types for the user-initiated "Copy Last Transcription"
    // write (planning 0019). Applied so well-behaved clipboard managers skip recording
    // dictated content — same rationale as 0007. The automated cycle never touches
    // the clipboard (planning 0011); only this explicit user action does.
    static let pasteboardMarkerTypes: [String] = [
        "org.nspasteboard.TransientType",
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.AutoGeneratedType",
    ]

    // Mic level (planning 0020). The publish interval throttles the level publisher
    // to ~14 Hz (the indicator smooths per display frame, far below the ~43
    // buffers/sec the tap delivers); the reference RMS is the linear amplitude that
    // maps to a full level of 1.
    //
    // The reference was 0.2 (about -14 dBFS) to match the study page's `rms / 0.2`.
    // On-device that mapping left loud speech below level 0.3 and full scale
    // unreachable: a browser applies automatic gain control to its mic, while
    // `AVAudioEngine` delivers the raw signal, so the same voice lands far lower here
    // (maintainer's smoke, 2026-09-17). Lowering the reference scales every level
    // threshold down together and leaves the indicator's own tuned numbers untouched.
    // Conservative first value: room tone has been measured near 0.02 RMS in places
    // (see `silenceTrimEnergyThreshold`), which must stay well below the waking range.
    static let inputLevelPublishInterval: Double = 0.07
    static let inputLevelReferenceRMS: Float = 0.08
}
