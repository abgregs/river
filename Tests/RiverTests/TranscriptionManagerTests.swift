import Foundation
import Testing
@testable import River

@Suite("TranscriptionManager model load state")
struct TranscriptionManagerLoadStateTests {
    // planning 0004: the initial load state is set from a synchronous disk check
    // at init time so the menu bar shows the right label before `loadModel()` runs.

    @MainActor
    @Test("initial modelLoadState is downloading or loading (never ready before loadModel)")
    func initialLoadStateIsNotReady() {
        // On a machine without the model cached (CI), state is .downloading.
        // On a machine with the cache, state is .loading. Either is correct —
        // neither is .ready, which would be a lie before the model is warm.
        let mgr = TranscriptionManager()
        #expect(mgr.currentModelLoadState != .ready)
        #expect(mgr.currentModelLoadState != .failed)
    }

    @MainActor
    @Test("setModelLoadStateForTesting drives currentModelLoadState")
    func testSeamDrivesState() {
        let mgr = TranscriptionManager()
        mgr.setModelLoadStateForTesting(.ready)
        #expect(mgr.currentModelLoadState == .ready)
        mgr.setModelLoadStateForTesting(.loading)
        #expect(mgr.currentModelLoadState == .loading)
    }

    @MainActor
    @Test("modelLoadState publisher emits the current value on subscribe")
    func publisherEmitsCurrentValueOnSubscribe() {
        let mgr = TranscriptionManager()
        var received: [ModelLoadState] = []
        let token = mgr.modelLoadState.sink { received.append($0) }
        defer { token.cancel() }
        // CurrentValueSubject delivers the current value immediately on subscribe.
        #expect(received.count == 1)
        #expect(received.first == mgr.currentModelLoadState)
    }

    @MainActor
    @Test("isModelCached returns false when the model directory does not exist")
    func isModelCachedFalseWhenMissing() {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ff-test-\(UUID().uuidString)", isDirectory: true)
        #expect(!WhisperKitLoader.isModelCached(downloadBase: temp, modelName: "openai_whisper-small.en"))
    }
}

@Suite("TranscriptionManager model switch")
struct TranscriptionManagerModelSwitchTests {
    // planning 0021: the picker switches models off-cycle. `prepareModelSwitch` is the
    // synchronous half — it re-points the manager and re-enters the 0004 load window
    // so the menu bar can't keep showing "Ready" for a model that isn't loaded yet.

    @MainActor
    @Test("prepareModelSwitch re-points the model and re-enters the load window")
    func switchRepointsAndReloads() {
        let mgr = TranscriptionManager(modelName: "openai_whisper-small.en")
        mgr.setModelLoadStateForTesting(.ready)   // pretend the first model is warm
        let changed = mgr.prepareModelSwitch(to: "openai_whisper-base.en")
        #expect(changed)
        #expect(mgr.currentModelName == "openai_whisper-base.en")
        // Re-entered the honest load window — never left showing "Ready" for a model
        // that is not actually loaded (planning 0004/0021 AC3). On CI the new model is
        // uncached (.downloading); with a cache it's .loading — either is honest.
        #expect(mgr.currentModelLoadState != .ready)
        #expect(mgr.currentModelLoadState != .failed)
    }

    @MainActor
    @Test("prepareModelSwitch to the already-active model is a no-op")
    func switchToSameModelIsNoOp() {
        let mgr = TranscriptionManager(modelName: "openai_whisper-small.en")
        mgr.setModelLoadStateForTesting(.ready)
        let changed = mgr.prepareModelSwitch(to: "openai_whisper-small.en")
        #expect(!changed)
        #expect(mgr.currentModelName == "openai_whisper-small.en")
        #expect(mgr.currentModelLoadState == .ready)   // untouched — no needless reload
    }

    // planning 0036, Model: a new model takes over only once it is ready. Until then the
    // user can still dictate, so the model in use, and the state the menu bar and the
    // recording gate read, must not move.
    @MainActor
    @Test("a new model loads beside a ready one, which stays in use until the switch commits")
    func readyModelStaysInUseUntilCommit() async {
        let mgr = stagingManager()
        await mgr.switchModel(to: "openai_whisper-base.en")
        #expect(mgr.currentModelName == "openai_whisper-small.en")
        #expect(mgr.currentModelLoadState == .ready)
        #expect(mgr.currentModelSwitch == ModelSwitch(target: "openai_whisper-base.en", phase: .ready))

        #expect(mgr.commitModelSwitch())
        #expect(mgr.currentModelName == "openai_whisper-base.en")
        #expect(mgr.currentModelSwitch == nil)
        #expect(!mgr.commitModelSwitch())   // nothing left to commit
    }

    @MainActor
    @Test("a failed new model leaves the one in use, and choosing it again retries")
    func failedStageKeepsCurrentAndRetries() async {
        let loader = FakeModelLoader()
        let mgr = stagingManager(loader)
        loader.failing = ["openai_whisper-base.en"]
        await mgr.switchModel(to: "openai_whisper-base.en")
        #expect(mgr.currentModelSwitch?.phase == .failed)
        #expect(!mgr.commitModelSwitch())
        #expect(mgr.currentModelName == "openai_whisper-small.en")
        #expect(mgr.currentModelLoadState == .ready)

        loader.failing = []
        await mgr.switchModel(to: "openai_whisper-base.en")
        #expect(mgr.currentModelSwitch?.phase == .ready)
    }

    @MainActor
    @Test("choosing the model in use again drops the switch in progress")
    func choosingCurrentDropsSwitch() async {
        let mgr = stagingManager()
        await mgr.switchModel(to: "openai_whisper-base.en")
        await mgr.switchModel(to: "openai_whisper-small.en")
        #expect(mgr.currentModelSwitch == nil)
        #expect(!mgr.commitModelSwitch())
        #expect(mgr.currentModelName == "openai_whisper-small.en")
    }

    // The first download, or a model that never loaded: there is nothing to keep using, so
    // waiting beside it would only delay the user's choice.
    @MainActor
    @Test("with no ready model, a new choice replaces the current one at once", arguments: [ModelLoadState.downloading, .loading, .failed])
    func noReadyModelReplacesAtOnce(state: ModelLoadState) async {
        let mgr = stagingManager()
        mgr.setModelLoadStateForTesting(state)
        await mgr.switchModel(to: "openai_whisper-base.en")
        #expect(mgr.currentModelName == "openai_whisper-base.en")
        #expect(mgr.currentModelSwitch == nil)
    }

    // A failed load was a dead end that needed a relaunch (planning 0026, item 4).
    @MainActor
    @Test("choosing a failed model again loads it again")
    func failedModelRetries() async {
        let mgr = stagingManager()
        mgr.setModelLoadStateForTesting(.failed)
        await mgr.switchModel(to: "openai_whisper-small.en")
        #expect(mgr.currentModelLoadState != .failed)
    }

    @MainActor
    private func stagingManager(_ loader: FakeModelLoader? = nil) -> TranscriptionManager {
        let mgr = TranscriptionManager.withFake(loader ?? FakeModelLoader(), modelName: "openai_whisper-small.en")
        mgr.setModelLoadStateForTesting(.ready)
        return mgr
    }
}

@Suite("Curated model list")
struct CuratedModelListTests {
    // planning 0021: the picker is driven by `Constants.curatedModels`. This pins the
    // load-bearing invariants — the default is selectable and every entry is complete —
    // so a dropped default or a half-filled row is a failing test, not silent drift.

    @MainActor
    @Test("the curated list includes the default model")
    func includesDefault() {
        #expect(Constants.curatedModels.contains { $0.name == Constants.defaultModel })
    }

    @MainActor
    @Test("every entry fills each column the catalogue shows")
    func entriesAreComplete() {
        for model in Constants.curatedModels {
            #expect(!model.name.isEmpty)
            #expect(!model.label.isEmpty)
            #expect(!model.provider.isEmpty)
            #expect(!model.family.isEmpty)
            #expect(!model.summary.isEmpty)
            #expect(model.downloadMegabytes > 0)
        }
    }

    // The default is what a fresh install downloads, on every Mac River supports (macOS 14):
    // a default that needed a newer macOS would leave a macOS 14 Mac with no model at all.
    @MainActor
    @Test("the default model runs on River's oldest supported macOS")
    func defaultRunsOnOldestMacOS() throws {
        let model = try #require(Constants.curatedModels.first { $0.name == Constants.defaultModel })
        #expect(model.minimumMacOS <= 14)
    }

    @MainActor
    @Test("model names are unique (Picker tags must not collide)")
    func namesAreUnique() {
        let names = Constants.curatedModels.map(\.name)
        #expect(Set(names).count == names.count)
    }
}

@Suite("TranscriptionManager with no model loaded")
struct TranscriptionManagerGateTests {
    @MainActor
    @Test("transcribe throws .modelNotLoaded when loadModel has not completed")
    func transcribeThrowsWhenModelNotLoaded() async {
        // Per ADR 0001, success-path transcription is integration-tested
        // manually (a real WhisperKit load is too heavy for the unit suite).
        // The fail-fast surface — calling transcribe before the model is
        // loaded — is what stops the live text's stream when the user
        // dictates before the model has finished downloading: it then decodes
        // from there in one piece at release. That contract belongs to a fast
        // unit test.
        let service = TranscriptionManager()
        await #expect(throws: TranscriptionError.self) {
            _ = try await service.transcribe(audioSamples: [0.0, 0.1, 0.2])
        }
    }
}

@Suite("TranscriptionManager model cache location")
struct TranscriptionCacheLocationTests {
    // The model must download under Application Support, never ~/Documents —
    // Documents is TCC-protected, so downloading there triggers a Documents-folder
    // prompt and clutters the user's Documents (planning 0010). This pins the
    // location so a regression to WhisperKit's ~/Documents default fails loudly.
    @MainActor
    @Test("the default download base resolves under Application Support, not Documents")
    func downloadBaseUnderApplicationSupport() {
        let path = ModelStore.defaultDownloadBase().path
        #expect(path.contains("/Library/Application Support/\(Constants.modelCacheFolderName)"))
        #expect(!path.contains("/Documents"))
    }
}

@Suite("WhisperKitModel empty-prompt retry")
struct TranscriptionEmptyPromptRetryTests {
    // The dictionary-can-only-help guarantee (custom-dictionary.md): a prompted
    // decode that comes back empty must retry unprompted, so adding a dictionary
    // term never turns a working dictation into a hard `.emptyTranscription`.
    // Exercised through the narrow decode seam (ADR 0001) — a fake `decode`
    // closure, no live WhisperKit model.

    @MainActor
    @Test("prompted-empty falls back to the unprompted retry and returns its text")
    func promptedEmptyRetriesUnprompted() async throws {
        // Prompted decode degenerates to empty; unprompted yields text. The retry
        // must fire and its text — not an error — is what the user gets.
        var calls: [[Int]] = []
        let text = try await WhisperKitModel.resolveWithEmptyPromptRetry(promptTokens: [1, 2, 3]) { tokens in
            calls.append(tokens)
            return tokens.isEmpty ? "hello" : ""
        }
        #expect(text == "hello")
        #expect(calls == [[1, 2, 3], []])   // prompted first, then the unprompted retry
    }

    @MainActor
    @Test("a genuinely silent recording (both decodes empty) still throws .emptyTranscription")
    func bothEmptyThrows() async {
        // The retry degrades a bad prompt to neutral, not error — but honest
        // failure must survive: if the audio itself is silent, both decodes are
        // empty and the cycle must still surface `.emptyTranscription`.
        await #expect(throws: TranscriptionError.self) {
            _ = try await WhisperKitModel.resolveWithEmptyPromptRetry(promptTokens: [1, 2, 3]) { _ in "" }
        }
    }

    @MainActor
    @Test("no prompt: an empty decode throws without a spurious retry")
    func noPromptEmptyThrowsWithoutRetry() async {
        // With no prompt in play there is nothing to degrade to, so an empty
        // decode is an honest empty result — it must not trigger a second call.
        var callCount = 0
        await #expect(throws: TranscriptionError.self) {
            _ = try await WhisperKitModel.resolveWithEmptyPromptRetry(promptTokens: []) { _ in
                callCount += 1
                return ""
            }
        }
        #expect(callCount == 1)   // no retry when there was no prompt to blame
    }

    @MainActor
    @Test("annotation-only output classifies as .noSpeechDetected, not .emptyTranscription")
    func annotationOnlyThrowsNoSpeechDetected() async {
        // Decode gates don't reliably suppress non-speech — probed on-device:
        // real room tone decodes to "[BLANK_AUDIO]" (planning 0023). That text
        // must never paste, and it must classify as the quiet no-op case (the
        // session skips it silently) rather than the loud .emptyTranscription.
        do {
            _ = try await WhisperKitModel.resolveWithEmptyPromptRetry(promptTokens: []) { _ in "[BLANK_AUDIO]" }
            Issue.record("expected .noSpeechDetected to be thrown")
        } catch TranscriptionError.noSpeechDetected {
            // expected: quiet no-op classification
        } catch {
            Issue.record("wrong error: \(error) — the session would show the error glyph")
        }
    }

    @MainActor
    @Test("a prompted annotation-only decode triggers the unprompted retry")
    func promptedAnnotationRetriesUnprompted() async throws {
        // Annotation-only is "no speech" for retry purposes too: a prompt that
        // degenerates decoding to "[BLANK_AUDIO]" must get the same second
        // chance as one that degenerates to empty — the dictionary can only help.
        var calls: [[Int]] = []
        let text = try await WhisperKitModel.resolveWithEmptyPromptRetry(promptTokens: [1, 2, 3]) { tokens in
            calls.append(tokens)
            return tokens.isEmpty ? "hello" : "[BLANK_AUDIO]"
        }
        #expect(text == "hello")
        #expect(calls == [[1, 2, 3], []])
    }
}

@Suite("WhisperKitModel non-speech annotation detector")
struct TranscriptionAnnotationDetectorTests {
    // Pure whole-output classifier for Whisper's non-speech labels. The probe
    // clips (planning 0023) produced exactly these shapes: "[BLANK_AUDIO]"
    // (quiet room), "[MUSIC]" (keyboard), "(heavy breathing)" (breath). A false
    // positive here would silently drop real dictation, so the negative cases
    // matter as much as the positives.

    @MainActor
    @Test("recognizes the observed annotation forms")
    func recognizesObservedForms() {
        #expect(WhisperKitModel.isNonSpeechAnnotation("[BLANK_AUDIO]"))
        #expect(WhisperKitModel.isNonSpeechAnnotation("(heavy breathing)"))
        #expect(WhisperKitModel.isNonSpeechAnnotation("[MUSIC]"))
        #expect(WhisperKitModel.isNonSpeechAnnotation(" [BLANK_AUDIO] "))
    }

    @MainActor
    @Test("recognizes multi-segment and punctuation-trailing annotations")
    func recognizesCompositeForms() {
        // WhisperKit joins segments with spaces, and models often append a
        // period — leftover punctuation must not defeat the classification.
        #expect(WhisperKitModel.isNonSpeechAnnotation("[BLANK_AUDIO] [BLANK_AUDIO]"))
        #expect(WhisperKitModel.isNonSpeechAnnotation("(sighs)."))
        #expect(WhisperKitModel.isNonSpeechAnnotation("[MUSIC] (heavy breathing)"))
    }

    @MainActor
    @Test("never classifies output containing real words")
    func neverEatsRealSpeech() {
        // Mixed annotation+speech keeps the speech — whole-output check only.
        #expect(!WhisperKitModel.isNonSpeechAnnotation("Hello world"))
        #expect(!WhisperKitModel.isNonSpeechAnnotation("Hello (laughs) world"))
        #expect(!WhisperKitModel.isNonSpeechAnnotation("[MUSIC] turn it up"))
    }

    @MainActor
    @Test("empty and annotation-free punctuation are NOT annotations")
    func emptyAndBarePunctuationAreNot() {
        // Empty is `.emptyTranscription`'s territory, and punctuation-only output
        // with no bracketed label present is left alone — classification requires
        // at least one annotation to have matched.
        #expect(!WhisperKitModel.isNonSpeechAnnotation(""))
        #expect(!WhisperKitModel.isNonSpeechAnnotation("   "))
        #expect(!WhisperKitModel.isNonSpeechAnnotation("..."))
    }
}

@Suite("WhisperKitModel prompt-token filter")
struct TranscriptionFilterTests {
    // The custom-dictionary prompt feeds raw token IDs into WhisperKit's
    // `DecodingOptions.promptTokens`. WhisperKit's tokenizer also emits
    // "special" tokens (timestamps, language tags, sentinels) starting at
    // `tokenizer.specialTokens.specialTokenBegin`. Letting one slip into the
    // prompt silently corrupts decoding — the output looks like noise.
    // The filter is the structural guard. Tests pin it on synthetic inputs.

    @MainActor
    @Test("drops tokens at or above specialTokenBegin")
    func dropsAtAndAboveThreshold() {
        let filtered = WhisperKitModel.filterSpecialTokens(
            [0, 5, 100, 50_256, 50_257, 50_258],
            specialTokenBegin: 50_257
        )
        #expect(filtered == [0, 5, 100, 50_256])
    }

    @MainActor
    @Test("passes everything below the threshold through unchanged")
    func passesBelowThreshold() {
        let filtered = WhisperKitModel.filterSpecialTokens(
            [1, 2, 3, 12_345],
            specialTokenBegin: 50_257
        )
        #expect(filtered == [1, 2, 3, 12_345])
    }

    @MainActor
    @Test("empty input returns empty output")
    func emptyInput() {
        #expect(WhisperKitModel.filterSpecialTokens([], specialTokenBegin: 50_257).isEmpty)
    }

    @MainActor
    @Test("threshold of zero filters every token (boundary)")
    func zeroThresholdFiltersAll() {
        // Defensive: if a future tokenizer reports `specialTokenBegin == 0`,
        // we must not pass a single token through (the filter is `<`, not `<=`).
        let filtered = WhisperKitModel.filterSpecialTokens([0, 1, 2, 999], specialTokenBegin: 0)
        #expect(filtered.isEmpty)
    }
}

@Suite("TranscriptionManager short clips")
struct TranscriptionManagerShortClipTests {
    // The maintainer's smoke (2026-09-26): quick taps of "hi" and "yes" under about a
    // second decoded to nothing until silence surrounded them; with half a second each
    // side, the same recordings transcribed.
    @Test("a clip under 1.2 s gets half a second of silence on each side")
    func shortClipIsPadded() {
        let clip = [Float](repeating: 0.1, count: 12_000)
        let padded = TranscriptionManager.paddedForDecoding(clip)
        let pad = Int(Constants.shortClipPadSeconds * 16_000)
        #expect(Constants.shortClipSeconds == 1.2)
        #expect(Constants.shortClipPadSeconds == 0.5)
        #expect(padded.count == clip.count + 2 * pad)
        #expect(padded.prefix(pad).allSatisfy { $0 == 0 } && padded.suffix(pad).allSatisfy { $0 == 0 })
        #expect(Array(padded[pad..<(pad + clip.count)]) == clip)
    }

    // Padding a longer clip hurt some real recordings in the replay, so it stays exact.
    @Test("a clip of 1.2 s or longer is decoded as captured")
    func longClipIsUntouched() {
        let clip = [Float](repeating: 0.1, count: Int(Constants.shortClipSeconds * 16_000))
        #expect(TranscriptionManager.paddedForDecoding(clip) == clip)
    }

    @Test("an empty clip stays empty")
    func emptyStaysEmpty() {
        #expect(TranscriptionManager.paddedForDecoding([]).isEmpty)
    }
}

@Suite("WhisperKitLoader tokenizer file check")
struct TranscriptionManagerTokenizerCheckTests {
    // A tokenizer folder with `tokenizer.json` and `config.json` but no usable
    // `tokenizer_config.json` sends swift-transformers to its `Hub` resource bundle,
    // which River.app lacks: a `fatalError`, so every launch would crash. The check
    // must turn that folder into a typed load error before WhisperKit reads it, and
    // must pass the complete folders a normal download leaves.

    private static let model = "openai_whisper-small.en"

    private static func makeBase() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("river-tokenizer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    // Writes a tokenizer folder where WhisperKit's Hub search looks first.
    private static func writeTokenizer(in base: URL, tokenizerConfig: String?) throws {
        let dir = base.appendingPathComponent("models/openai/whisper-small.en", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type": "whisper"}"#.utf8).write(to: dir.appendingPathComponent("config.json"))
        try Data(#"{"model": {}}"#.utf8).write(to: dir.appendingPathComponent("tokenizer.json"))
        if let tokenizerConfig {
            try Data(tokenizerConfig.utf8).write(to: dir.appendingPathComponent("tokenizer_config.json"))
        }
    }

    private static func isUnusableTokenizerError(_ error: any Error) -> Bool {
        if case .unusableTokenizerConfig(folderName: "whisper-small.en") = error as? TranscriptionError { return true }
        return false
    }

    @MainActor
    @Test("a missing tokenizer_config.json throws a typed load error")
    func missingTokenizerConfigThrows() throws {
        let base = try Self.makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.writeTokenizer(in: base, tokenizerConfig: nil)
        #expect(performing: {
            try WhisperKitLoader.checkTokenizerFiles(downloadBase: base, modelName: Self.model)
        }, throws: Self.isUnusableTokenizerError)
    }

    @MainActor
    @Test("a tokenizer_config.json without a tokenizer_class string throws", arguments: [
        #"{"chat_template": "x"}"#,
        #"{"tokenizer_class": null}"#,
        "not json",
    ])
    func tokenizerConfigWithoutClassThrows(tokenizerConfig: String) throws {
        let base = try Self.makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.writeTokenizer(in: base, tokenizerConfig: tokenizerConfig)
        #expect(performing: {
            try WhisperKitLoader.checkTokenizerFiles(downloadBase: base, modelName: Self.model)
        }, throws: Self.isUnusableTokenizerError)
    }

    @MainActor
    @Test("a complete tokenizer folder passes")
    func completeTokenizerPasses() throws {
        let base = try Self.makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.writeTokenizer(in: base, tokenizerConfig: #"{"tokenizer_class": "WhisperTokenizer"}"#)
        try WhisperKitLoader.checkTokenizerFiles(downloadBase: base, modelName: Self.model)
    }

    @MainActor
    @Test("no tokenizer on disk passes, so WhisperKit can fetch it")
    func emptyCachePasses() throws {
        let base = try Self.makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        try WhisperKitLoader.checkTokenizerFiles(downloadBase: base, modelName: Self.model)
    }
}

/// A temporary download base laid out as WhisperKit and its Hub leave one, so the
/// downloaded check and Delete run against fixture files, never the user's models.
@MainActor
private struct ModelFixture {
    let base: URL

    init() throws {
        base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("river-models-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: base) }

    func modelFolder(_ name: String) -> URL { WhisperKitLoader.modelFolder(downloadBase: base, modelName: name) }
    var records: URL { base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/.cache/huggingface/download") }
    var tokenizer: URL { base.appendingPathComponent("models/openai/whisper-small.en") }

    // Every file the repo ships for a model, each `bytes` long, and its download records.
    func writeModel(_ name: String, prefill: Bool = false, bytes: Int = 1) throws {
        let models = ["MelSpectrogram", "AudioEncoder", "TextDecoder"] + (prefill ? ["TextDecoderContextPrefill"] : [])
        let files = ["config.json", "generation_config.json"] + models.flatMap { model in
            ["coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin", "analytics/coremldata.bin"]
                .map { "\(model).mlmodelc/\($0)" }
        }
        for file in files {
            try write(modelFolder(name).appendingPathComponent(file), bytes: bytes)
            try write(records.appendingPathComponent("\(name)/\(file).metadata"), bytes: 1)
        }
    }

    func writeTokenizer() throws {
        try write(tokenizer.appendingPathComponent("tokenizer.json"), bytes: 1)
    }

    func write(_ file: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: file)
    }

    func removeFile(_ path: String, of name: String) throws {
        try FileManager.default.removeItem(at: modelFolder(name).appendingPathComponent(path))
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

@Suite("WhisperKitLoader downloaded check")
struct TranscriptionManagerDownloadedCheckTests {
    // planning 0026 finding 3, 0038: a cut-off download used to read as downloaded because
    // one file was there. "Downloaded", the Delete offer and the warm-launch load all rely on
    // the check, so a model reads as downloaded only with every file it needs.

    private static let model = "openai_whisper-small.en"

    @MainActor
    @Test("a complete model folder reads as downloaded")
    func completeFolderIsCached() throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeModel(Self.model)
        #expect(WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: Self.model))
    }

    @MainActor
    @Test("a folder missing any one file reads as not downloaded", arguments: [
        "config.json",
        "generation_config.json",
        "MelSpectrogram.mlmodelc/weights/weight.bin",
        "AudioEncoder.mlmodelc/coremldata.bin",
        "TextDecoder.mlmodelc/model.mil",
        "TextDecoder.mlmodelc/analytics/coremldata.bin",
    ])
    func partialFolderIsNotCached(missing: String) throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeModel(Self.model)
        try fixture.removeFile(missing, of: Self.model)
        #expect(!WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: Self.model))
    }

    @MainActor
    @Test("the leftovers of a cut-off download, the AudioEncoder alone, read as not downloaded")
    func audioEncoderAloneIsNotCached() throws {
        // The old check's false positive: a 1.3 MB base.en folder seen on device (2026-08-14).
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.modelFolder(Self.model).appendingPathComponent("AudioEncoder.mlmodelc/coremldata.bin"), bytes: 1)
        #expect(!WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: Self.model))
    }

    @MainActor
    @Test("a prefill model's folder must be complete too, since WhisperKit loads it when it is there")
    func partialPrefillIsNotCached() throws {
        let model = "openai_whisper-large-v3-v20240930_turbo"
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeModel(model, prefill: true)
        #expect(WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: model))
        try fixture.removeFile("TextDecoderContextPrefill.mlmodelc/weights/weight.bin", of: model)
        #expect(!WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: model))
    }
}

@Suite("TranscriptionManager delete model")
struct TranscriptionManagerDeleteModelTests {
    // planning 0038: Delete frees a model's space, and must never take the files of the
    // model River transcribes with or of one loading beside it, which would break dictation
    // or a load mid-read. Every test deletes from a temporary folder.

    private static let inUse = "openai_whisper-small.en"
    private static let other = "openai_whisper-base.en"

    @MainActor
    @Test("deleting a downloaded model removes its folder and records, and it reads as not downloaded")
    func deleteRemovesFolderAndRecords() throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeModel(Self.other)
        let manager = TranscriptionManager(modelName: Self.inUse, store: ModelStore(downloadBase: fixture.base))
        try manager.deleteModel(named: Self.other)
        #expect(!fixture.exists(fixture.modelFolder(Self.other)))
        #expect(!fixture.exists(fixture.records.appendingPathComponent(Self.other)))
        #expect(!WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: Self.other))
    }

    @MainActor
    @Test("a delete leaves the model in use, other models and the shared tokenizer folders")
    func deleteLeavesEverythingElse() throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeModel(Self.inUse)
        try fixture.writeModel(Self.other)
        try fixture.writeModel("distil-whisper_distil-large-v3")
        try fixture.writeTokenizer()
        let manager = TranscriptionManager(modelName: Self.inUse, store: ModelStore(downloadBase: fixture.base))
        try manager.deleteModel(named: Self.other)
        #expect(WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: Self.inUse))
        #expect(WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: "distil-whisper_distil-large-v3"))
        #expect(fixture.exists(fixture.records.appendingPathComponent(Self.inUse)))
        #expect(fixture.exists(fixture.tokenizer.appendingPathComponent("tokenizer.json")))
    }

    @MainActor
    @Test("the model in use is refused, whatever its load state", arguments: [ModelLoadState.ready, .loading, .downloading, .failed])
    func modelInUseIsRefused(state: ModelLoadState) throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeModel(Self.inUse)
        let manager = TranscriptionManager(modelName: Self.inUse, store: ModelStore(downloadBase: fixture.base))
        manager.setModelLoadStateForTesting(state)
        #expect(throws: ModelDeletionError.inUse) {
            try manager.deleteModel(named: Self.inUse)
        }
        #expect(WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: Self.inUse))
    }

    @MainActor
    @Test("the model loading beside the one in use is refused, ready or failed", arguments: [false, true])
    func modelLoadingBesideIsRefused(fails: Bool) async throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeModel(Self.other)
        let loader = FakeModelLoader()
        if fails { loader.failing = [Self.other] }
        let manager = TranscriptionManager.withFake(loader, modelName: Self.inUse, downloadBase: fixture.base)
        manager.setModelLoadStateForTesting(.ready)
        await manager.switchModel(to: Self.other)
        #expect(manager.currentModelSwitch?.target == Self.other)
        #expect(throws: ModelDeletionError.loading) {
            try manager.deleteModel(named: Self.other)
        }
        #expect(WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: Self.other))
    }

    @MainActor
    @Test("a name outside the catalogue is refused, so a delete can only take a model's own folder")
    func unknownNameIsRefused() throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeTokenizer()
        let manager = TranscriptionManager(modelName: Self.inUse, store: ModelStore(downloadBase: fixture.base))
        #expect(throws: ModelDeletionError.notInCatalogue) {
            try manager.deleteModel(named: "../../openai")
        }
        #expect(fixture.exists(fixture.tokenizer.appendingPathComponent("tokenizer.json")))
    }

    @MainActor
    @Test("what a delete frees is measured on disk: the model's folder and its records")
    func freedSpaceIsMeasured() throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeModel(Self.other, bytes: 100_000)
        let freed = ModelStore(downloadBase: fixture.base).spaceFreed(byDeleting: Self.other)
        // 17 files of 100 kB, plus 17 one-byte records, each taking at least a block.
        #expect(freed >= 17 * 100_000)
        #expect(freed == ModelStore.diskUsage(of: fixture.modelFolder(Self.other))! + ModelStore.diskUsage(of: fixture.records.appendingPathComponent(Self.other))!)
        let before = try #require(ModelStore.diskUsage(of: ModelStore(downloadBase: fixture.base).modelsFolder))
        let manager = TranscriptionManager(modelName: Self.inUse, store: ModelStore(downloadBase: fixture.base))
        try manager.deleteModel(named: Self.other)
        let after = ModelStore.diskUsage(of: ModelStore(downloadBase: fixture.base).modelsFolder) ?? 0
        #expect(before - after == freed)
    }
}

/// Manual offline-load check (planning 0004 follow-up) — env-gated like the eval
/// harness, because it needs a model River has already downloaded. A cached model
/// must load with no network: warm launches used to ask Hugging Face for the file
/// list first, which cost seconds and failed outright offline. Run it in a process
/// the sandbox denies network access, so the check can only pass from disk
/// (`--disable-sandbox` stops SwiftPM applying its own sandbox inside this one,
/// which macOS refuses):
///
///   swift build --build-tests && RIVER_OFFLINE_LOAD=1 sandbox-exec -p '(version 1)(allow default)(deny network*)' swift test --skip-build --disable-sandbox --filter CachedModelOfflineLoad
///
///   Optional: RIVER_OFFLINE_LOAD_MODEL=openai_whisper-small.en  (default: base.en, the fastest to load)
@Suite("CachedModelOfflineLoad")
struct CachedModelOfflineLoadTests {
    @MainActor
    @Test(
        "a cached model reaches ready with the network blocked",
        .enabled(if: ProcessInfo.processInfo.environment["RIVER_OFFLINE_LOAD"] != nil)
    )
    func cachedModelLoadsOffline() async throws {
        let model = ProcessInfo.processInfo.environment["RIVER_OFFLINE_LOAD_MODEL"] ?? "openai_whisper-base.en"
        try #require(
            WhisperKitLoader.isModelCached(downloadBase: ModelStore.defaultDownloadBase(), modelName: model),
            "\(model) is not downloaded; pick it in River once, then rerun"
        )
        let manager = TranscriptionManager(modelName: model)
        try await manager.loadModel()
        #expect(manager.currentModelLoadState == .ready)
    }
}

@Suite("TranscriptionManager engines")
struct TranscriptionManagerEngineTests {
    // planning 0037: the switching logic is written once, and each model loads through its own
    // engine's loader, picked from its catalogue entry.
    private static let parakeet = "parakeet-tdt-0.6b-v2-coreml"
    private static let phonon = "phonon-2-coreml"
    // Every FluidAudio model the catalogue lists, so one added to the catalogue alone fails
    // the tests below rather than shipping a row that never downloads or loads.
    private static let fluidAudioModels = Constants.curatedModels.filter { $0.engine == .fluidAudio }.map(\.name)

    @MainActor
    @Test("a model loads through its own engine's loader, and transcribes once it takes over")
    func modelLoadsThroughItsEngine() async throws {
        let whisper = FakeModelLoader()
        let fluid = FakeModelLoader()
        let mgr = TranscriptionManager(modelName: Constants.defaultModel, store: ModelStore(loaders: { $0 == .fluidAudio ? fluid : whisper }))
        try await mgr.loadModel()
        #expect(whisper.loads == [Constants.defaultModel])

        await mgr.switchModel(to: Self.parakeet)
        #expect(fluid.loads == [Self.parakeet])
        #expect(whisper.loads == [Constants.defaultModel])
        // Until the switch commits, dictation keeps the model in use.
        #expect(try await mgr.transcribe(audioSamples: [0.1]) == Constants.defaultModel)
        #expect(mgr.commitModelSwitch())
        #expect(try await mgr.transcribe(audioSamples: [0.1]) == Self.parakeet)
    }

    // A saved name River can't load would leave the user with no model at all: one from an
    // older catalogue has no engine, and Phonon-2 needs macOS 15.
    @MainActor
    @Test("a saved model this Mac can't run falls back to the default")
    func unrunnableSavedModelFallsBack() {
        #expect(TranscriptionManager.runnableModel("openai_whisper-tiny.en", macOSMajor: 15) == Constants.defaultModel)
        #expect(TranscriptionManager.runnableModel(Self.phonon, macOSMajor: 14) == Constants.defaultModel)
        #expect(TranscriptionManager.runnableModel(Self.phonon, macOSMajor: 15) == Self.phonon)
        #expect(TranscriptionManager.runnableModel(Self.parakeet, macOSMajor: 14) == Self.parakeet)
        let mgr = TranscriptionManager.withFake(FakeModelLoader(), modelName: "openai_whisper-tiny.en")
        #expect(mgr.currentModelName == Constants.defaultModel)
    }

    // planning 0038: the Model section's folder total, Show in Finder and Delete read one
    // models folder, so every engine must keep its models inside it.
    @MainActor
    @Test("every catalogue model's files sit inside the one models folder")
    func everyModelIsInsideTheModelsFolder() {
        let base = URL(fileURLWithPath: "/tmp/river-base", isDirectory: true)
        let store = ModelStore(downloadBase: base)
        let models = store.modelsFolder.path + "/"
        for option in Constants.curatedModels {
            let folder = store.folder(of: option.name)
            #expect(folder != nil, "\(option.name) has no folder")
            let paths = [folder].compactMap { $0 } + store.files(of: option.name)
            for path in paths.map(\.path) { #expect(path.hasPrefix(models), "\(option.name): \(path)") }
        }
    }

    @MainActor
    @Test("a FluidAudio model with no files, or one River doesn't list, is not downloaded")
    func fluidAudioDownloadedCheck() throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        let loader = FluidAudioLoader()
        try fixture.write(loader.folder(of: Self.parakeet, downloadBase: fixture.base).appendingPathComponent("Encoder.mlmodelc/model.mil.partial"), bytes: 1)
        #expect(!loader.isDownloaded(Self.parakeet, downloadBase: fixture.base))
        #expect(!loader.isDownloaded("parakeet-tdt-0.6b-v3-coreml", downloadBase: fixture.base))
    }

    // planning 0037: `FluidAudioLoader` keeps its own table of FluidAudio's versions and repos,
    // since the catalogue can't name FluidAudio's types. A catalogue entry missing from it
    // would read as never downloaded and fail every load.
    @MainActor
    @Test("every FluidAudio model in the catalogue is one FluidAudioLoader knows")
    func catalogueFluidAudioModelsAreKnown() {
        #expect(!Self.fluidAudioModels.isEmpty)
        for name in Self.fluidAudioModels { #expect(FluidAudioLoader.models[name] != nil, "\(name)") }
    }

    // A name the catalogue doesn't list reaches no loader, so no engine guesses at it: it has
    // no folder for Show in Finder, nothing for a delete to remove, and its load fails.
    @MainActor
    @Test("a name the catalogue doesn't list has no folder or files, isn't downloaded, and fails to load")
    func unlistedNameReachesNoLoader() async {
        let loader = FakeModelLoader()
        loader.downloaded = ["openai_whisper-tiny.en"]
        let store = ModelStore(loaders: { _ in loader })
        #expect(store.folder(of: "openai_whisper-tiny.en") == nil)
        #expect(store.files(of: "openai_whisper-tiny.en").isEmpty)
        #expect(!store.isDownloaded("openai_whisper-tiny.en"))
        await #expect(throws: ModelStoreError.notInCatalogue) {
            _ = try await store.load("openai_whisper-tiny.en", phase: { _ in }, progress: { _ in })
        }
        #expect(loader.loads.isEmpty)
    }

    // The files FluidAudio 0.18.3 writes for each model, as on the maintainer's Mac
    // (2026-11-19): a compiled model is a folder holding `coremldata.bin`.
    private static let fluidAudioFiles = [
        parakeet: ["Preprocessor", "Encoder", "Decoder", "JointDecision"].map { "\($0).mlmodelc/coremldata.bin" }
            + ["parakeet_vocab.json", "config.json"],
        phonon: ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"].map { "\($0).mlmodelc/coremldata.bin" }
            + ["parakeet_vocab.json", "parakeet_v3_vocab.json", "config.json"],
    ]

    @MainActor
    private func writeFluidAudioModel(_ name: String, in fixture: ModelFixture) throws -> URL {
        let folder = FluidAudioLoader().folder(of: name, downloadBase: fixture.base)
        for file in Self.fluidAudioFiles[name] ?? [] { try fixture.write(folder.appendingPathComponent(file), bytes: 1) }
        return folder
    }

    // PR 7a smoke test (2026-11-19): FluidAudio names its folder `phonon-2`, not after the
    // repo's `-coreml` name, so a guessed folder left Show in Finder and Delete pointing at
    // nothing. FluidAudio's own check reading the files where River says they are ties the two.
    @MainActor
    @Test("FluidAudio finds a model in the folder River shows and deletes", arguments: fluidAudioModels)
    func fluidAudioFolderIsWhereFluidAudioLooks(model: String) throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        let folder = try writeFluidAudioModel(model, in: fixture)
        #expect(FluidAudioLoader().isDownloaded(model, downloadBase: fixture.base))
        #expect(!folder.lastPathComponent.hasSuffix("-coreml"))
    }

    @MainActor
    @Test("deleting a FluidAudio model removes its folder, so it reads as not downloaded, and leaves the Whisper models")
    func deleteFluidAudioModel() throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        try fixture.writeModel(Constants.defaultModel)
        let folder = try writeFluidAudioModel(Self.parakeet, in: fixture)
        let mgr = TranscriptionManager(modelName: Constants.defaultModel, store: ModelStore(downloadBase: fixture.base))
        try mgr.deleteModel(named: Self.parakeet)
        #expect(!fixture.exists(folder))
        #expect(!FluidAudioLoader().isDownloaded(Self.parakeet, downloadBase: fixture.base))
        #expect(WhisperKitLoader.isModelCached(downloadBase: fixture.base, modelName: Constants.defaultModel))
    }
}

@Suite("TranscriptionManager download progress")
struct TranscriptionManagerDownloadProgressTests {
    // planning 0004: the status ring and Settings show how far a download has got. The manager
    // publishes it apart from the selection, only while its model downloads, and never lower.
    private static let small = Constants.defaultModel
    private static let base = "openai_whisper-base.en"

    @MainActor
    @Test("a download's fraction is published under its model's name, never falls, and ends once preparing starts")
    func fractionLastsWhileDownloading() async throws {
        let loader = FakeModelLoader()
        loader.held = [Self.small]
        let mgr = TranscriptionManager.withFake(loader)
        #expect(mgr.currentModelLoadState == .downloading)
        let load = Task { try await mgr.loadModel() }
        await loader.loadStarted(Self.small)

        loader.report(progress: 0.4, of: Self.small)
        #expect(mgr.currentDownloadProgress == [Self.small: 0.4])
        // A report that lands late, below one already shown, would move the arc backwards.
        loader.report(progress: 0.3, of: Self.small)
        #expect(mgr.currentDownloadProgress == [Self.small: 0.4])

        loader.report(.loading, of: Self.small)
        #expect(mgr.currentDownloadProgress.isEmpty)
        // Preparing has no fraction: a report landing now is from the finished download.
        loader.report(progress: 0.9, of: Self.small)
        #expect(mgr.currentDownloadProgress.isEmpty)

        loader.finishLoad(of: Self.small)
        try await load.value
        #expect(mgr.currentModelLoadState == .ready)
    }

    @MainActor
    @Test("a model loading beside the one in use reports its own download, and the one in use stays ready")
    func stagedModelReportsItsOwnDownload() async throws {
        let loader = FakeModelLoader()
        let mgr = TranscriptionManager.withFake(loader)
        try await mgr.loadModel()
        loader.held = [Self.base]
        let choice = Task { await mgr.switchModel(to: Self.base) }
        await loader.loadStarted(Self.base)

        loader.report(progress: 0.5, of: Self.base)
        #expect(mgr.currentDownloadProgress == [Self.base: 0.5])
        #expect(mgr.currentModelLoadState == .ready)

        loader.finishLoad(of: Self.base)
        await choice.value
        #expect(mgr.currentModelSwitch == ModelSwitch(target: Self.base, phase: .ready))
        #expect(mgr.currentDownloadProgress.isEmpty)
        // A late report must not put a model that is ready to take over back to downloading.
        loader.report(.downloading, of: Self.base)
        #expect(mgr.currentModelSwitch == ModelSwitch(target: Self.base, phase: .ready))
    }

    @MainActor
    @Test("a load a newer choice replaced reports nothing, so only the model being waited for shows")
    func supersededLoadReportsNothing() async {
        let loader = FakeModelLoader()
        loader.held = [Self.small, Self.base]
        let mgr = TranscriptionManager.withFake(loader)
        let first = Task { try? await mgr.loadModel() }
        await loader.loadStarted(Self.small)
        let choice = Task { await mgr.switchModel(to: Self.base) }
        await loader.loadStarted(Self.base)

        loader.report(progress: 0.7, of: Self.small)
        loader.report(.loading, of: Self.small)
        #expect(mgr.currentDownloadProgress.isEmpty)
        #expect(mgr.currentModelLoadState == .downloading)
        loader.report(progress: 0.2, of: Self.base)
        #expect(mgr.currentDownloadProgress == [Self.base: 0.2])

        loader.finishLoad(of: Self.small)
        loader.finishLoad(of: Self.base)
        await first.value
        await choice.value
        #expect(mgr.currentModelName == Self.base)
        #expect(mgr.currentModelLoadState == .ready)
    }

    @MainActor
    @Test("a load's fraction ends with it, and a report landing after it never reopens the state", arguments: [false, true])
    func loadEndsItsReports(fails: Bool) async {
        let loader = FakeModelLoader()
        loader.held = [Self.small]
        if fails { loader.failing = [Self.small] }
        let mgr = TranscriptionManager.withFake(loader)
        let load = Task { try? await mgr.loadModel() }
        await loader.loadStarted(Self.small)
        loader.report(progress: 0.5, of: Self.small)
        loader.finishLoad(of: Self.small)
        await load.value
        let settled: ModelLoadState = fails ? .failed : .ready
        #expect(mgr.currentModelLoadState == settled)
        #expect(mgr.currentDownloadProgress.isEmpty)

        // FluidAudio reports from a queue of its own, so a report can reach the main actor after
        // its load has returned. Taken, it would show Preparing for a model that is ready.
        loader.report(.loading, of: Self.small)
        loader.report(progress: 0.6, of: Self.small)
        #expect(mgr.currentModelLoadState == settled)
        #expect(mgr.currentDownloadProgress.isEmpty)
    }
}

@Suite("WhisperKitLoader download progress")
struct WhisperKitLoaderDownloadProgressTests {
    // planning 0004: WhisperKit's own progress counts files, and two weight files hold nearly
    // all of a model, so River measures the bytes on disk against the catalogue's size.
    private static let small = "openai_whisper-small.en"

    @Test("the bytes on disk give the fraction of the catalogue's size")
    func fractionOfCatalogueSize() {
        #expect(WhisperKitLoader.downloadFraction(bytes: 0, megabytes: 487) == 0)
        #expect(WhisperKitLoader.downloadFraction(bytes: 243_500_000, megabytes: 487) == 0.5)
    }

    @Test("the fraction stops short of done until the download ends, since the size is a measurement")
    func fractionStopsShortOfDone() {
        #expect(WhisperKitLoader.downloadFraction(bytes: 487_000_000, megabytes: 487) == Constants.downloadProgressCeiling)
        #expect(WhisperKitLoader.downloadFraction(bytes: 600_000_000, megabytes: 487) == Constants.downloadProgressCeiling)
    }

    @Test("a model with no size to measure against reports no progress rather than a made-up one")
    func noSizeReportsNothing() {
        #expect(WhisperKitLoader.downloadFraction(bytes: 1_000, megabytes: 0) == 0)
    }

    @MainActor
    @Test("a download counts its model's files and the parts still coming in, not other models or the tokenizer")
    func measuresItsOwnFiles() throws {
        let fixture = try ModelFixture()
        defer { fixture.remove() }
        let folders = WhisperKitLoader.downloadFolders(downloadBase: fixture.base, modelName: Self.small)
        try fixture.writeModel(Self.small, bytes: 10_000)
        let whole = WhisperKitLoader.bytesOnDisk(in: folders)
        #expect(whole >= 17 * 10_000)

        // The Hub writes a file still coming in beside the records, and moves it in once whole:
        // while a weight file downloads, that part is nearly all the download.
        let part = fixture.records.appendingPathComponent("\(Self.small)/AudioEncoder.mlmodelc/weights/weight.bin.0123abcd.incomplete")
        try fixture.write(part, bytes: 50_000)
        let withPart = WhisperKitLoader.bytesOnDisk(in: folders)
        #expect(withPart - whole >= 50_000)

        try fixture.writeModel("openai_whisper-base.en", bytes: 30_000)
        try fixture.writeTokenizer()
        #expect(WhisperKitLoader.bytesOnDisk(in: folders) == withPart)
    }
}

@Suite("FluidAudioLoader download progress")
struct FluidAudioLoaderDownloadProgressTests {
    // planning 0004: FluidAudio 0.18.3 reports each model call's repo download as the first half
    // of that call's fraction and its compile as the rest, so River scales the download back up.

    @Test("the download report of the call that fetches the files is scaled to the whole download")
    func scalesTheDownloadShare() {
        #expect(FluidAudioLoader.downloadFraction(0, filesToDownload: 12) == 0)
        #expect(FluidAudioLoader.downloadFraction(0.25, filesToDownload: 12) == 0.5)
        #expect(FluidAudioLoader.downloadFraction(0.5, filesToDownload: 12) == 1)
    }

    @Test("a call that finds the files on disk carries no fraction")
    func nothingToFetchCarriesNoFraction() {
        // It reports its download as done without fetching anything, so the arc would fill
        // for a download that never ran.
        #expect(FluidAudioLoader.downloadFraction(0.5, filesToDownload: 0) == nil)
    }
}

@Suite("TranscriptionManager waiting for the model")
struct TranscriptionManagerWaitTests {
    // planning 0004: a dictation that ends before the model is ready waits for it, then types.
    // The wait follows the published state: ready ends it, a failed load ends it with an error,
    // and downloading, preparing or a newer choice keep it waiting.
    private static let small = Constants.defaultModel
    private static let base = "openai_whisper-base.en"

    private enum Outcome: Equatable { case ready, failed, cancelled, other }

    // How the wait ended. One still open after 200 turns of the main actor, a second when it is
    // idle, is cancelled, so a wait that never ends fails the test rather than hanging the run.
    // Turns, not a clock: in a parallel run other suites hold the main actor too.
    @MainActor
    private static func outcome(of wait: Task<Void, Error>) async -> Outcome {
        let deadline = Task { @MainActor in
            for _ in 0..<200 { try await Task.sleep(nanoseconds: 5_000_000) }
            wait.cancel()
        }
        defer { deadline.cancel() }
        do {
            try await wait.value
            return .ready
        } catch TranscriptionError.modelLoadFailed {
            return .failed
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .other
        }
    }

    // A wait that has started, and a held load of `model` running under it.
    @MainActor
    private static func waitDuringLoad(_ loader: FakeModelLoader, _ mgr: TranscriptionManager, of model: String) async -> Task<Void, Error> {
        loader.held.insert(model)
        Task { try? await mgr.loadModel() }
        await loader.loadStarted(model)
        let wait = Task { try await mgr.waitUntilReady() }
        for _ in 0..<200 where mgr.openWaitCount == 0 { try? await Task.sleep(nanoseconds: 5_000_000) }
        return wait
    }

    @MainActor
    @Test("a ready model ends the wait at once, and a failed one fails it at once")
    func settledStateEndsTheWaitAtOnce() async {
        let mgr = TranscriptionManager.withFake(FakeModelLoader())
        mgr.setModelLoadStateForTesting(.ready)
        #expect(await Self.outcome(of: Task { try await mgr.waitUntilReady() }) == .ready)
        mgr.setModelLoadStateForTesting(.failed)
        #expect(await Self.outcome(of: Task { try await mgr.waitUntilReady() }) == .failed)
        #expect(mgr.openWaitCount == 0)
    }

    @MainActor
    @Test("the wait lasts through downloading and preparing, and ends once the model is ready")
    func waitEndsWhenReady() async {
        let loader = FakeModelLoader()
        let mgr = TranscriptionManager.withFake(loader)
        let wait = await Self.waitDuringLoad(loader, mgr, of: Self.small)
        #expect(mgr.openWaitCount == 1)
        loader.report(.loading, of: Self.small)
        #expect(mgr.openWaitCount == 1)

        loader.finishLoad(of: Self.small)
        #expect(await Self.outcome(of: wait) == .ready)
        #expect(mgr.currentModelLoadState == .ready)
        #expect(mgr.openWaitCount == 0)
    }

    @MainActor
    @Test("a load that fails ends the wait with modelLoadFailed, so the dictation can keep its recording")
    func failedLoadFailsTheWait() async {
        let loader = FakeModelLoader()
        loader.failing = [Self.small]
        let mgr = TranscriptionManager.withFake(loader)
        let wait = await Self.waitDuringLoad(loader, mgr, of: Self.small)
        loader.finishLoad(of: Self.small)
        #expect(await Self.outcome(of: wait) == .failed)
        #expect(mgr.currentModelLoadState == .failed)
    }

    @MainActor
    @Test("a model chosen during the wait is waited for in place of the one it replaced")
    func waitFollowsANewChoice() async {
        let loader = FakeModelLoader()
        loader.failing = [Self.small]
        let mgr = TranscriptionManager.withFake(loader)
        let wait = await Self.waitDuringLoad(loader, mgr, of: Self.small)
        loader.held.insert(Self.base)
        let choice = Task { await mgr.switchModel(to: Self.base) }
        await loader.loadStarted(Self.base)

        // The replaced load failing is not the new model failing.
        loader.finishLoad(of: Self.small)
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(mgr.openWaitCount == 1)

        loader.finishLoad(of: Self.base)
        await choice.value
        #expect(await Self.outcome(of: wait) == .ready)
        #expect(mgr.currentModelName == Self.base)
    }

    @MainActor
    @Test("a wait with no load running starts one, so it can never wait forever")
    func waitStartsAMissingLoad() async {
        let loader = FakeModelLoader()
        let mgr = TranscriptionManager.withFake(loader)
        #expect(mgr.currentModelLoadState == .downloading)
        #expect(await Self.outcome(of: Task { try await mgr.waitUntilReady() }) == .ready)
        #expect(loader.loads == [Self.small])
    }

    @MainActor
    @Test("cancelling the waiting task ends the wait, and the model keeps loading")
    func cancelEndsTheWait() async {
        let loader = FakeModelLoader()
        let mgr = TranscriptionManager.withFake(loader)
        let wait = await Self.waitDuringLoad(loader, mgr, of: Self.small)
        wait.cancel()
        #expect(await Self.outcome(of: wait) == .cancelled)
        #expect(mgr.openWaitCount == 0)
        #expect(mgr.currentModelLoadState == .downloading)

        loader.finishLoad(of: Self.small)
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(mgr.currentModelLoadState == .ready)
    }
}
