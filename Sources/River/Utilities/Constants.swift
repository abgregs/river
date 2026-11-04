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

    // Audio kept in memory while the microphone is ready, and seeded into the next
    // recording so a word spoken at the instant of the press keeps its onset (planning
    // 0033, decision 2). Equal to `silenceTrimLeadSeconds`: a longer window only adds
    // audio the trim discards, and holds more of what was said before the press.
    static let preRollSeconds: Double = 0.5

    // A recording whose audio falls short of its wall time by more than this is reported as
    // a capture failure instead of transcribed. Under `AVAudioEngine` the engine stopped
    // when the audio device changed and nothing told the recording: a 14 s first recording
    // with AirPods captured 1.5 s and typed nothing (2026-09-24 trace). The capture unit now
    // restarts when its selected device changes, so this catches a restart that failed or a
    // pinned device that stopped delivering. The bound is absolute, not a share of the recording: 2.5 min
    // missing from a 5 min dictation is as lost as 2.5 s from 5 s. The gap is counted from
    // the first buffer, not from the start call: the engine's own start measured 0.91 s on
    // a loaded machine with AirPods (2026-10-23, `AVAudioEngine`; the HAL unit's start-up
    // is not yet measured), which would have cut a healthy recording short. What remains is a restart's lost window plus up to one buffer in flight at
    // release. Measured 2026-10-23: a mid-recording switch from AirPods to the built-in
    // microphone cost 0.48 s and the text spanned the switch, so 1 s leaves the restart
    // about half its budget.
    static let captureGapMaximumSeconds: Double = 1.0
    // Before the first buffer there is no gap to measure, only a capture unit that has not
    // delivered. Past this the watchdog ends the recording so the user is not left talking
    // to a dead microphone; a slow but live start (0.91 s measured) stays well inside it.
    static let captureStartTimeoutSeconds: Double = 3.0
    // How often a recording checks that gap while it runs. Buffers stop when the capture
    // unit dies, so the gap grows with the clock and a check every second catches the loss
    // within two seconds; the recording then ends on its own instead of running on while
    // the user talks to a dead microphone. Decided 2026-10-23: a tight bound on purpose,
    // tuned later only against measured false positives.
    static let captureWatchdogIntervalSeconds: Double = 1.0

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

    // River's mark, 川 (docs/design/kawa-identity.md). The shapes live in `KawaMark`, in their
    // own design units.

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

    // The HUD surface every floating shape shares: an opaque tint (`Palette.HUD`, following
    // Light and Dark mode) and a lit glass edge (below). Opaque since 2026-11-04 (maintainer): a
    // crisp, high-contrast panel that looks the same over any desktop, so nothing behind it
    // changes how the mark or the text reads.
    // The lit edge, chosen on the Glass study (docs/design/studies/kawa/kawa-glass-r1.html,
    // maintainer, 2026-11-03): the panel is a thin sheet lit from the upper left, at the angle
    // Glass lights its ripples from, so the mark and its panel share one light. A 1 pt rim inside
    // the edge is brightest at that corner and dies away along the edges into a shade at the far
    // corner; a sheen falls across the tint from the same corner; the far edges carry a soft
    // shade inside; a dark outer line holds the edge over light desktops. The edge lies over the
    // content, so text and the frost never cover it.
    //
    // The light's direction in CSS degrees (0 points up, 90 right), as the study draws it.
    static let hudLightAngle: Double = 147
    // Each appearance's opacities (below) scale by these: edge light, far-edge shade, sheen.
    static let hudEdgeLight: Double = 1.5
    static let hudFarEdgeShade: Double = 1.2
    static let hudSheen: Double = 1.0
    // Along the light, the rim is bright at the first stop and fades through the next two; the
    // shade is at its end. The sheen is gone by `hudSheenReach`.
    static let hudRimStops: [Double] = [0, 0.26, 0.58]
    static let hudSheenReach: Double = 0.52
    static let hudRimWidth: Double = 1
    static let hudOuterLineWidth: Double = 0.5
    // The inner shade: the outside of the edge moved toward the light and blurred, so it falls
    // inside the far edges only.
    static let hudInnerShadeOffsetX: Double = -2
    static let hudInnerShadeOffsetY: Double = -3
    static let hudInnerShadeRadius: Double = 3
    // Dark: the rim's three stops, the far-edge shade, the sheen, the inner shade, the outer line.
    static let hudDarkRimOpacities: [Double] = [0.62, 0.22, 0.05]
    static let hudDarkFarEdgeShadeOpacity: Double = 0.4
    static let hudDarkSheenOpacity: Double = 0.085
    static let hudDarkInnerShadeOpacity: Double = 0.3
    static let hudDarkOuterLineOpacity: Double = 0.6
    // Light: white light only shows on the light tint near full strength, so the rim and sheen
    // run brighter and the shades lighter; a black outer line at the dark value would read as a
    // frame.
    static let hudLightRimOpacities: [Double] = [1, 0.75, 0.35]
    static let hudLightFarEdgeShadeOpacity: Double = 0.1
    static let hudLightSheenOpacity: Double = 0.5
    static let hudLightInnerShadeOpacity: Double = 0.07
    static let hudLightOuterLineOpacity: Double = 0.14
    // Two shadows, drawn outside the edge only, falling
    // straight down like every window's: the panel shares the screen's light, whatever lights
    // its edge. A wide soft one, and a tight one where the panel meets the desktop. Each opacity
    // scales by `hudShadowStrength`; the radii are half the study's CSS blur, as SwiftUI's
    // shadow radius is about the blur's standard deviation.
    static let hudShadowStrength: Double = 1.4
    static let hudShadowOpacity: Double = 0.34
    static let hudShadowRadius: Double = 11
    static let hudShadowOffset: Double = 8
    static let hudContactShadowOpacity: Double = 0.22
    static let hudContactShadowRadius: Double = 1
    static let hudContactShadowOffset: Double = 1
    // Secondary text on the HUD (a toast's hint, the notice): the text color at this opacity.
    // The system `.secondary` renders it at 0.5, about 3.0:1 on the light surface; 0.8 holds
    // 4.5:1 on both tints (PaletteTests).
    static let hudSecondaryTextOpacity: Double = 0.8
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

    // The kawa indicator (docs/design/kawa-identity.md): every number below was tuned on the
    // study page (docs/design/studies/kawa/kawa-studies-r1.html) and approved by the maintainer on
    // 2026-11-02; they are ported as is. The choreography lives in `KawaIndicatorTimeline`, the
    // voice in `KawaIndicatorEngine`.
    //
    // Entry: the panel fades in, then the muted strokes on a sine ease-in-out; the Glass layer
    // starts the overlap before the strokes are in, so the two flow into each other.
    static let kawaPanelInSeconds: Double = 0.22
    static let kawaPanelRise: Double = 6
    static let kawaMutedDelaySeconds: Double = 0.08
    static let kawaMutedFadeSeconds: Double = 0.45
    static let kawaLayerOverlapSeconds: Double = 0.2
    // The muted strokes' opacity: one value for Glass and for preparing.
    static let kawaMutedOpacity: Double = 0.2
    // Exit: the layer leaves just after release over this long; the panel fades over its own time.
    static let kawaLayerOutDelaySeconds: Double = 0.05
    static let kawaLayerOutSeconds: Double = 0.4
    static let kawaPanelOutSeconds: Double = 0.3
    // Reduce Motion: every envelope becomes a linear fade this long.
    static let kawaReducedFadeSeconds: Double = 0.2

    // The voice: one shared level, stepped at a fixed rate so it is the same at any frame rate.
    // It rises fast and falls slowly, with a ±18 % jitter re-drawn on its own clock so it never
    // sits perfectly still while you speak.
    static let kawaEngineStepsPerSecond: Double = 240
    static let kawaLevelRiseSeconds: Double = 0.05
    static let kawaLevelFallSeconds: Double = 0.25
    static let kawaLevelJitter: Double = 0.36
    static let kawaLevelJitterClockSeconds: Double = 0.06

    // Glass: a pane of frost over the strokes. While the level is above the threshold, drops
    // fall on the strokes at a steady cadence, each in one of three tiers (soft, normal, raised)
    // picked by the loudest level since the previous drop.
    static let kawaGlassCadence: Double = 2
    static let kawaGlassRippleSize: Double = 1.6
    static let kawaGlassSensitivity: Double = 0.6
    static let kawaGlassThreshold: Double = 0.32 - 0.26 * kawaGlassSensitivity
    static let kawaGlassNormalFrom: Double = 0.32
    static let kawaGlassLoudFrom: Double = 0.6
    // Glass's look was retuned on the Glass study (docs/design/studies/kawa/kawa-glass-r1.html,
    // maintainer, 2026-11-03), so a normal voice plainly shows, a raised one more, and the
    // frosted and cleared states read apart. Per tier, soft to raised: the ring's strength,
    // which sets its light and its bend, and the radius of the window it clears in the frost,
    // in points: small for soft, about the mark's width for normal, most of the panel for raised.
    static let kawaGlassRingStrengths: [Double] = [0.6, 1.2, 1.4]
    static let kawaGlassWindowRadii: [Double] = [12, 20, 28]
    // A window holds open this long after its drop, then fades back to frost over this, on the
    // clock that stops at release.
    static let kawaGlassWindowHoldSeconds: Double = 1.2
    static let kawaGlassWindowFadeSeconds: Double = 0.6
    // A ripple's front travels this fast, in points a second, and its rings are this far apart,
    // in points; both scale with the ripple's size (front by its square root, rings by the size).
    static let kawaGlassRippleSpeed: Double = 16
    static let kawaGlassWavelength: Double = 3.4
    // A drop's ripple lasts this long. The shader reads it too, so a ripple and the drop that
    // makes it end together.
    static let kawaGlassRippleSeconds: Double = 2.2 * kawaGlassRippleSize.squareRoot()
    // The engine keeps a drop while its ripple or its window may still show, so a window never
    // snaps shut instead of fading.
    static let kawaGlassDropSeconds: Double = max(kawaGlassRippleSeconds, kawaGlassWindowHoldSeconds + kawaGlassWindowFadeSeconds)
    // The shader: how far a ripple bends the strokes and how bright its light (the study's
    // sliders, 0…1); the frost's strength, its blur radius in points and its veil, each scaled
    // by the frost's strength; the grain in the veil; and how strong the ink is under the frost
    // and where the voice has cleared it.
    static let kawaGlassRefraction: Double = 0.4
    static let kawaGlassHighlights: Double = 0.8
    // The shader's scale for each slider: the study multiplies its 0…1 refraction and light by
    // these before they reach the shader, so the sliders above copy across from the study as is.
    static let kawaGlassRefractionScale: Double = 1.6
    static let kawaGlassHighlightScale: Double = 1.4
    static let kawaGlassFrost: Double = 0.72
    static let kawaGlassBlur: Double = 1.2
    static let kawaGlassVeil: Double = 0.6
    static let kawaGlassGrain: Double = 0.24
    static let kawaGlassFrostedInk: Double = 0.45
    static let kawaGlassClearInk: Double = 0.9
    // How strongly a ripple's light and its shade on the far side show, per appearance
    // (`Palette.HUD` holds their colors).
    static let kawaGlassDarkHighlightAmount: Double = 0.55
    static let kawaGlassDarkShadeAmount: Double = 0.5
    static let kawaGlassLightHighlightAmount: Double = 0.75
    static let kawaGlassLightShadeAmount: Double = 0.22
    // The frost forms evenly and the ink rises under it over these, together.
    static let kawaGlassFormSeconds: Double = 0.6
    static let kawaGlassInkSeconds: Double = 0.6

    // The indicator reads loudness in decibels of full scale (dBFS); a linear scale left quiet
    // speech invisible on a built-in mic (maintainer's smoke, 2026-09-24). The floor is the
    // capture trim's floor, so the indicator never moves for a recording the trim then discards
    // as silence: a voice layer that moved for a dictation River threw away would claim it heard
    // you. Below the floor it reads silence, so motion always means sound; the ceiling reads as
    // full. Display only: it reads `inputLevel`, which the capture path never uses.
    // The ceiling sits at raised speech and a curve keeps quiet speech low, so soft, normal
    // and raised read apart: at -28 dBFS with no curve, quiet speech filled half the scale and
    // normal speech nearly all of it (maintainer's level trace, 2026-11-02: built-in mic, quiet
    // room -62, soft speech to about -39, normal to about -33, raised to about -22 and peaks
    // near -15).
    static let markMeterFloorDecibels: Double = 20 * log10(Double(silenceTrimFloor))
    static let markMeterCeilingDecibels: Double = -16
    static let markMeterCurve: Double = 1.5
    // Menu bar glyphs: the mark in an 18 pt image (docs/design/kawa-identity.md). Ready is 川,
    // 16 pt tall. While River listens or transcribes, 川 steps down to 14 pt, left of centre, and
    // a dot sits at the top right: red while the microphone records, then muted ink while River
    // transcribes, the same dot at a reduced strength. Every state is the same 18 pt, so the
    // icons beside it never shift.
    static let menuBarGlyphSize: Double = 18
    static let menuBarMarkHeight: Double = 16
    static let menuBarSignedMarkHeight: Double = 14
    static let menuBarSignedMarkCentre = CGPoint(x: 7.6, y: 10)
    // The dot's box, top-left origin in points.
    static let menuBarSign = CGRect(x: 13, y: 0.6, width: 4.4, height: 4.4)
    // Transcribing's dot: the bar's text color at this strength, the least that still holds 3:1
    // on the modelled light and dark bars (docs/design/color.md).
    static let menuBarMutedDotOpacity: Double = 0.55

    // App icon: 川 in ink on a charcoal squircle (maintainer, 2026-10-29), drawn on
    // Apple's 1024 grid where the rounded square occupies 824 of the canvas.
    static let appIconCanvas: Double = 1024
    static let appIconSquircleInset: Double = 100
    static let appIconCornerRadius: Double = 185.4
    // The mark's height as a fraction of the squircle's.
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
    // to ~14 Hz, each reading the loudest buffer since the last (the indicator smooths per
    // display frame, far below the ~93 buffers/sec the capture unit delivers); the
    // reference RMS is the linear amplitude that maps to a full level of 1. The indicator
    // converts the level back to decibels (`markMeter*`), so the reference only sets where
    // the level clips: -12 dBFS, above the indicator's ceiling. At 0.08 (-22 dBFS) it
    // clipped raised speech before the indicator could read it (maintainer's level trace,
    // 2026-11-02).
    static let inputLevelPublishInterval: Double = 0.07
    static let inputLevelReferenceRMS: Float = 0.25
}
