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
    // Gap between the HUD panel and the bottom of the active screen's visible frame.
    static let hudBottomMargin: Double = 120

    // The pixel mark (planning 0029). Every number was tuned on the study page
    // (docs/design/studies/pixel-identity.html) and is ported as is, except the meter's
    // level reference, which is calibrated on device.

    // Geometry: 5 pt cells and 2 pt gaps make a 40 pt mark whose edges land on whole
    // pixels at 1x and 2x (the page's 4.5 pt cells fall on half pixels at 1x). The panel
    // keeps the 56 pt height of the river capsule it replaces and never changes size.
    static let pixelCell: Double = 5
    static let pixelGap: Double = 2
    static let pixelMarkSize: Double = 6 * pixelCell + 5 * pixelGap
    // Cell corners are this fraction of the cell at every size, so the mark keeps one roundness.
    static let pixelCornerFraction: Double = 0.16
    static let indicatorPanelHorizontalPadding: Double = 12
    static let indicatorPanelVerticalPadding: Double = 8
    static let indicatorPanelWidth: Double = pixelMarkSize + 2 * indicatorPanelHorizontalPadding
    static let indicatorPanelHeight: Double = pixelMarkSize + 2 * indicatorPanelVerticalPadding
    // The approved page's panel corner; a square mark takes a rounded square, not a capsule.
    static let indicatorPanelCornerRadius: Double = 13

    // The HUD surface: near-opaque charcoal, no material (a material flips the palette
    // per desktop). Dark appearance adds a hairline where the shadow vanishes.
    static let hudFillOpacityLight: Double = 0.96
    static let hudFillOpacityDark: Double = 0.94
    static let hudHairlineOpacity: Double = 0.07
    static let hudHairlineWidth: Double = 1
    // The CSS shadows `0 1 2` at 20% and `0 10 24` at 24%; the radius equals the CSS blur, matched side by side.
    static let hudNearShadowOffset: Double = 1
    static let hudNearShadowRadius: Double = 2
    static let hudNearShadowOpacity: Double = 0.20
    static let hudFarShadowOffset: Double = 10
    static let hudFarShadowRadius: Double = 24
    static let hudFarShadowOpacity: Double = 0.24
    // Transparent margin around the HUD content so the far shadow is not clipped by the panel.
    static let hudShadowMargin: Double = 48
    // Enter rises and exit drops by this much over `hudFadeSeconds`; Reduce Motion drops the rise.
    static let hudFadeRise: Double = 6

    // The rounded rectangle holding the toast, loading label, and notice, stacked with the capsule.
    static let hudMessageCornerRadius: Double = 16
    static let hudMessagePadding: Double = 12
    static let hudMessageWidth: Double = 260
    static let hudStackSpacing: Double = 8
    // Space always reserved below the capsule for that rectangle. The panel is this one
    // fixed size whatever it shows, so the capsule's position is arithmetic and a message
    // appearing or leaving can never move it (the shift the maintainer saw on cancel,
    // 2026-09-17, when a notice grew the content inside an already-sized panel).
    static let hudMessageReservedHeight: Double = 140

    // Motion. The drop and the return move all sixteen pixels at once on a strong ease-out;
    // the return is the quicker of the two, as an exit should be.
    static let pixelDropSeconds: Double = 0.26
    static let pixelReturnSeconds: Double = 0.24
    static let pixelEaseOut = (x1: 0.23, y1: 1.0, x2: 0.32, y2: 1.0)
    // Reduce Motion: no travel; the mark dips out and back while the layout swaps.
    static let pixelFadeThroughSeconds: Double = 0.24
    // Each pixel's ink and tint follow their target at this rate per second (about 0.17 s).
    static let pixelInkRate: Double = 18
    // The smoothed level Reduce Motion's meter follows: the river's attack and release.
    static let pixelLevelAttackRate: Double = 10
    static let pixelLevelReleaseRate: Double = 5
    // Longest frame interval the engine advances by, so a resumed timeline does not leap.
    static let pixelMaxFrameInterval: Double = 0.05

    // The meter: four columns, each its own readout, reading loudness in decibels of full
    // scale (dBFS); a linear scale left quiet speech invisible on a built-in mic
    // (maintainer's smoke, 2026-09-24). The floor is the capture trim's floor, so the meter
    // never lights for a recording the trim then discards as silence: a meter that moved
    // for a dictation River threw away would claim it heard you. The ceiling fills a
    // column. Display only: the meter reads `inputLevel`, which the capture path never uses.
    static let pixelMeterFloorDecibels: Double = 20 * log10(Double(silenceTrimFloor))
    static let pixelMeterCeilingDecibels: Double = -28
    // Silence keeps the bottom row half lit, so a quiet listening state never looks like rest.
    static let pixelMeterPilot: Double = 0.5
    // A slight center bias keeps the block balanced.
    static let pixelMeterGains: [Double] = [0.85, 1, 1, 0.85]
    // Each column re-reads the voice on its own clock, at a random interval in this range,
    // hearing it this late (shuffled, so syllables ripple through rather than sweep).
    static let pixelMeterTickRange: ClosedRange<Double> = 0.12...0.26
    static let pixelMeterHearDelays: [Double] = [0.06, 0, 0.12, 0.03]
    static let pixelMeterHistorySeconds: Double = 0.3
    // Each reading lands between this fraction and one more of the loudness's reach.
    static let pixelMeterSpreadFloor: Double = 0.25
    // Columns rise fast and fall slowly, like a level meter.
    static let pixelBarAttackRate: Double = 22
    static let pixelBarReleaseRate: Double = 6
    static let pixelUnlitInk: Double = 0.16
    static let pixelLitInk: Double = 0.95

    // Transcribing: a raised-cosine crest of full ink runs the stroke over a dimmed base,
    // the approved river crest carried over (its width is a fraction of the stroke here).
    static let pixelCrestHalfWidth: Double = 0.32
    static let pixelCrestRest: Double = 0.12
    static let pixelCrestPeriod: Double = 2.0
    static let pixelCrestBase: Double = 0.55
    // Preparing (the model getting ready at launch): the same crest, slower and over a dimmer
    // base, so it reads as waiting rather than working on your words.
    static let pixelPreparingCrestPeriod: Double = 3.0
    static let pixelPreparingCrestBase: Double = 0.4
    // The static Transcribing reading (menu bar, and the panel under Reduce Motion): every
    // other pixel dimmed. Removing them breaks the r apart; brighter reads as Ready.
    static let pixelDitherInk: Double = 0.3
    static let pixelIncreasedContrastInkFloor: Double = 0.4

    // Menu bar glyphs (planning 0029): the pixel r in an 18 pt template image, drawn denser
    // than the panel because 1 pt gaps at this size read as dots. Every cell edge lands on a
    // device pixel, so the grid sits at the box's origin rather than a half pixel off center.
    static let menuBarGlyphSize: Double = 18
    static let menuBarGlyphCell1x: Double = 2
    static let menuBarGlyphGap1x: Double = 1
    static let menuBarGlyphCell2x: Double = 2.5
    static let menuBarGlyphGap2x: Double = 0.5
    // Listening: a frozen meter reading with its bars out of step (2·3·4·1 reads as a
    // signal-strength icon).
    static let menuBarListeningHeights: [Int] = [3, 1, 4, 2]

    // App icon: the same pixel r in ink on a charcoal squircle, drawn on Apple's 1024
    // grid where the rounded square occupies 824 of the canvas. The accent stays off it
    // for now, so the icon matches the menu bar glyphs (maintainer, 2026-09-17).
    static let appIconCanvas: Double = 1024
    static let appIconSquircleInset: Double = 100
    static let appIconCornerRadius: Double = 185.4
    // The mark's width as a fraction of the squircle's.
    static let appIconMarkFraction: Double = 0.52
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
