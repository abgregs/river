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
    // discoverable fallback. Internal tunable, not a user setting (load-bearing rule
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
    // harness — see requirements/custom-dictionary.md). `small.en` (~240 MB) handles
    // prompts robustly and is more accurate, at some cost in speed/memory. The model
    // picker (planning 0021) lets speed-focused users drop back to `base.en`; this is
    // the default the `Settings.selectedModel` key sources.
    static let defaultModel: String = "openai_whisper-small.en"

    // PROVISIONAL curated list for the model picker (planning 0021). The final list
    // and default are decided by 0022's per-model scorecards, which don't exist yet —
    // these four are placeholders: the two known-good English models plus two stronger
    // candidates that have never been evaluated here. Names are the exact
    // `argmaxinc/whisperkit-coreml` repo folders WhisperKit downloads (verified against
    // WhisperKit 0.18's model tables). Sizes are approximate on-disk footprints. Each
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
            hint: "Balanced speed and accuracy (~240 MB). Current default."
        ),
        ModelOption(
            name: "distil-whisper_distil-large-v3",
            label: "Distil Large v3",
            hint: "High accuracy, distilled for speed (~600 MB)."
        ),
        ModelOption(
            name: "openai_whisper-large-v3-v20240930_turbo",
            label: "Large v3 Turbo",
            hint: "Most accurate, turbo decoding (~630 MB). Slowest to load."
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
    // dBFS (load-bearing rule #5). First-pass value: an on-device probe with
    // ad-hoc clips showed real room tone peaks ABOVE it (~0.02 RMS windows), so
    // the trim only catches near-digital silence; realistic near-silence is
    // handled by `TranscriptionManager.isNonSpeechAnnotation` instead. Tune
    // against the 0022 silence corpus once it's recorded.
    static let silenceTrimEnergyThreshold: Float = 0.01

    // Safety margin kept on each side of detected speech so onset/offset consonants
    // are never clipped by the trim. 100 ms at 16 kHz. See planning/0023.
    static let silenceTrimMarginSeconds: Double = 0.1

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
    // tunables, NOT settings: the HUD has no user-facing configuration (load-bearing
    // rule #5), so its timing, layout, and thresholds live here.

    // Fade in/out duration for the HUD panel. The panel is ordered out only after
    // this outlives the return to `.idle`, so the fade animation completes on screen
    // before the window is removed (planning 0002 acceptance criterion 2).
    static let hudFadeSeconds: Double = 0.22
    // Gap between the HUD panel and the bottom of the active screen's visible frame.
    static let hudBottomMargin: Double = 120

    // The river indicator (planning 0028). Every number was measured or tuned on the
    // study page (docs/design/studies/river-identity-studies.html) and is ported as is.

    // Geometry: the 108 x 40 mark is the strands' full range of motion; the capsule
    // adds side and vertical padding and never changes size.
    static let riverMarkWidth: Double = 108
    static let riverMarkHeight: Double = 40
    static let riverCapsuleHorizontalPadding: Double = 12
    static let riverCapsuleVerticalPadding: Double = 8
    static let riverCapsuleWidth: Double = riverMarkWidth + 2 * riverCapsuleHorizontalPadding
    static let riverCapsuleHeight: Double = riverMarkHeight + 2 * riverCapsuleVerticalPadding
    static let riverCapsuleCornerRadius: Double = riverCapsuleHeight / 2
    // Strand samples across the width, and the fraction at each end faded to nothing.
    static let riverSampleCount: Int = 57
    static let riverEndFadeFraction: Double = 0.14

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

    // Level engine, per display frame: attack and release rates per second (round two's timing).
    static let riverAttackRate: Double = 10
    static let riverReleaseRate: Double = 5
    // Motion floor: amplitude and width never fall below this level's shape.
    static let riverRestLevel: Double = 0.35
    // The strand clock runs at this fraction of real time at rest, rising to full speed with ink.
    static let riverRestSpeed: Double = 0.45
    // Ink and speed follow the level through a smoothstep over this span.
    static let riverInkSpan: Double = 0.5
    // Ink at rest, breathing by this depth at this angular rate (about seven seconds); still under Reduce Motion.
    static let riverRestInk: Double = 0.44
    static let riverBreathDepth: Double = 0.06
    static let riverBreathRate: Double = 0.9
    // The level the strands settle to while transcribing.
    static let riverTranscribingLevel: Double = 0.4
    // Longest frame interval the engine advances by, so a resumed timeline does not leap.
    static let riverMaxFrameInterval: Double = 0.05

    // Strand shape: y = base + amplitudeScale * motion * amp * (meander + rippleWeight * ripple).
    static let riverAmplitudeScale: Double = 11
    static let riverWidthGain: Double = 0.8
    static let riverMeanderDrift: Double = 0.6
    static let riverRippleDrift: Double = 1.9
    static let riverRippleWeight: Double = 0.45
    static let riverRipplePhaseGain: Double = 1.7
    static let riverStrands: [RiverStrand] = [
        RiverStrand(baseY: 11.5, amplitude: 0.7, meanderLength: 1.9, rippleLength: 0.62, phase: 0.4, speed: 0.55, width: 1.6, ink: 0.70),
        RiverStrand(baseY: 20, amplitude: 1.0, meanderLength: 1.45, rippleLength: 0.41, phase: 2.1, speed: 0.72, width: 2.6, ink: 1.00),
        RiverStrand(baseY: 28.5, amplitude: 0.8, meanderLength: 2.3, rippleLength: 0.53, phase: 4.0, speed: 0.61, width: 1.4, ink: 0.55),
    ]

    // Transcribing: a raised-cosine crest of full ink slides along each stroke once per
    // period over a dimmed base, each strand offset by a fraction of the period.
    static let riverCrestPeriod: Double = 2.0
    static let riverCrestWidth: Double = 70
    static let riverCrestStopCount: Int = 17
    static let riverCrestStagger: Double = 0.18
    static let riverCrestBase: Double = 0.55
    // The crest profile blends in and out at this rate per second (about 0.2 s).
    static let riverCrestBlendRate: Double = 12

    // Menu bar slat glyph (planning 0028): five slats in an 18 pt template image. The
    // studies' 16 pt mark read optically smaller than the neighboring status items and
    // sat a point low, so the box grew, the group widened, and the pitch opened from 2.5
    // to 3.5 (maintainer's smoke, 2026-09-17). The indicator keeps the study page's own
    // geometry. Rows are centered on the box at 2x, where stroke edges land on device
    // pixels; 1x cannot both center five rows and sit on pixel centers, so it keeps the
    // crisp rows and gives up half a point of centering.
    // The left x of each row, mirrored on the right.
    static let menuBarGlyphSize: Double = 18
    static let menuBarGlyphRowInsets: [Double] = [4.75, 2.25, 1.75, 2.25, 4.75]
    static let menuBarGlyphRowCenters1x: [Double] = [3.5, 6.5, 9.5, 12.5, 15.5]
    static let menuBarGlyphRowCenters2x: [Double] = [2, 5.5, 9, 12.5, 16]
    static let menuBarGlyphReadyStroke: Double = 1.6
    static let menuBarGlyphListeningStroke: Double = 1.9
    // Ready: the middle slat at full ink, the others dimmed.
    static let menuBarGlyphReadySideInk: Double = 0.55
    // Transcribing: dots per row, the first and last centered on the slat's endpoints.
    static let menuBarGlyphDotCounts: [Int] = [3, 4, 5, 4, 3]
    static let menuBarGlyphDotRadius: Double = 0.8

    // App icon: the same slat mark in ink on a charcoal squircle, drawn on Apple's 1024
    // grid where the rounded square occupies 824 of the canvas. The accent stays off it
    // for now, so the icon matches every other River mark (maintainer, 2026-09-17).
    static let appIconCanvas: Double = 1024
    static let appIconSquircleInset: Double = 100
    static let appIconCornerRadius: Double = 185.4
    // The mark's width as a fraction of the squircle's.
    static let appIconMarkFraction: Double = 0.58
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
