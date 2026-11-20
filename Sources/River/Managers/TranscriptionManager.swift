import Combine
import Foundation
import os

/// Load lifecycle for the transcription model, published so the menu bar can
/// show an honest status during the download/load window on launch.
///
/// State machine:
///   (cold) downloading → loading → ready
///   (warm)              loading → ready
///   (error) any        →          failed
enum ModelLoadState: Equatable {
    /// Model files are being fetched from the network (cold launch only).
    case downloading
    /// Files are on disk; CoreML models are loading into memory.
    case loading
    /// Model is warm and ready for inference.
    case ready
    /// Load failed. Choosing the same model again retries.
    case failed
}

/// A model loading beside the one in use (planning 0036, Model: a new model takes over only
/// once it is ready). The model in use keeps transcribing, and its `ModelLoadState` stays
/// `.ready`, until the session commits the switch at `.idle`.
struct ModelSwitch: Equatable {
    enum Phase: Equatable {
        case downloading
        case preparing
        /// Loaded and waiting for the session to commit it at `.idle`.
        case ready
        /// The model in use is unaffected; choosing the target again retries.
        case failed
    }

    let target: String
    var phase: Phase
}

/// Which model River uses and which takes over next (planning 0036, Model), as one value so
/// every reader sees a consistent pair: the Model section decides each row and its status line
/// from it, and the session commits a ready switch and saves the model in use from it.
struct ModelSelection: Equatable {
    /// The model `transcribe` runs.
    var inUse: String
    var inUseState: ModelLoadState
    /// A model loading beside it. Its `.ready` phase lasts only while a dictation is in
    /// progress: at `.idle` the session commits a ready switch at once.
    var next: ModelSwitch?
}

enum TranscriptionError: Error, LocalizedError {
    /// `transcribe` was called before `loadModel` completed. The session
    /// surfaces this in the log; M7 will fold it into the user-visible error
    /// surface alongside paste failures.
    case modelNotLoaded
    case transcriptionFailed(underlying: Error)
    /// The engine returned no text for a non-empty audio buffer. Distinct from
    /// the no-audio path (`AudioCaptureError.noAudioCaptured` in M5) so the
    /// log shows *what* failed.
    case emptyTranscription
    /// Whisper's decode produced only non-speech annotations (`[BLANK_AUDIO]`, `(heavy
    /// breathing)`, …), or a FluidAudio model wrote nothing: the model heard the audio but
    /// found no words in it. The
    /// session treats this like the all-silence trim case — quiet no-op, not a
    /// failure (planning 0023). Kept distinct from `.emptyTranscription` so the
    /// 0002/0018/0020 feedback surface can later explain "nothing was pasted"
    /// without conflating it with a real decode failure.
    case noSpeechDetected
    /// A tokenizer folder WhisperKit could load from has `tokenizer.json` and
    /// `config.json` but no `tokenizer_config.json` naming a `tokenizer_class`.
    /// Loading it would crash the app, so the load fails with this instead.
    /// `folderName` is the folder's last path component only (no user path).
    case unusableTokenizerConfig(folderName: String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model is not loaded yet."
        case .transcriptionFailed(let underlying):
            return "Transcription failed: \(underlying.localizedDescription)"
        case .emptyTranscription:
            return "Transcription returned no text."
        case .noSpeechDetected:
            return "No speech was detected in the recording."
        case .unusableTokenizerConfig(let folderName):
            return "The tokenizer files in \(folderName) are incomplete: tokenizer_config.json is missing or names no tokenizer class."
        }
    }
}

/// Why `TranscriptionManager.deleteModel` refused (planning 0038). The Model section offers
/// Delete only where none applies; a refusal means the state changed after the offer.
enum ModelDeletionError: Error, LocalizedError {
    case inUse
    case loading
    case notInCatalogue

    var errorDescription: String? {
        switch self {
        case .inUse: "River is using this model."
        case .loading: "River is loading this model. Try again once it has finished."
        case .notInCatalogue: "River doesn’t list this model."
        }
    }
}

@MainActor
final class TranscriptionManager {
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "transcribe")
    // The model in use drives `loadModel` and the cache path; `switchModel(to:)` changes it.
    private var modelName: String { selectionSubject.value.inUse }

    /// The models on this Mac and the loaders that run them (planning 0037, 0038): the real
    /// folder and loaders in the app, a temporary folder or a fake loader in tests. The Model
    /// section reads it too.
    let store: ModelStore

    private var model: (any LoadedModel)?
    private var loadTask: Task<any LoadedModel, Error>?
    // Bumped by every `prepareModelSwitch`; a `loadModel` run only commits its result
    // when its captured generation is still current, so a switch that supersedes an
    // in-flight load (e.g. the launch load) can't clobber the newer model's state.
    private var loadGeneration = 0

    // The next model, loading beside the one in use. Its own generation, so a newer
    // choice drops an older staged load's result.
    private var staged: (any LoadedModel)?
    private var stagedTask: Task<any LoadedModel, Error>?
    private var stageGeneration = 0

    // How many load tasks are reading each model's files. A choice that supersedes a load
    // cancels it, but cancellation is cooperative and the Core ML load runs on, so
    // `deleteModel` asks this as well as the selection.
    private var modelsLoading: [String: Int] = [:]

    // The one record of the model in use, its load state and the model loading beside it.
    // Every change sends a whole value, so no reader sees a half-made switch. Initialized from
    // a synchronous disk check so the first value is already correct when `bind(transcription:)`
    // subscribes in AppDelegate.
    private let selectionSubject: CurrentValueSubject<ModelSelection, Never>

    /// The model in use and the model loading beside it.
    var selection: AnyPublisher<ModelSelection, Never> { selectionSubject.eraseToAnyPublisher() }
    var currentSelection: ModelSelection { selectionSubject.value }

    /// The in-use model's load lifecycle: the menu bar shows an honest "Downloading…" /
    /// "Preparing…" / "Ready" from it.
    var modelLoadState: AnyPublisher<ModelLoadState, Never> {
        selectionSubject.map(\.inUseState).removeDuplicates().eraseToAnyPublisher()
    }

    /// Synchronous accessor for the session's model-readiness gate.
    var currentModelLoadState: ModelLoadState { selectionSubject.value.inUseState }
    // internal for testability — the model loading beside the one in use.
    var currentModelSwitch: ModelSwitch? { selectionSubject.value.next }

    /// User-curated terms that bias decoding toward proper nouns and jargon.
    /// M8 will wire `Settings.customDictionaryTerms` → `setCustomDictionaryTerms`.
    /// Until then, the list is empty; the special-token filter still runs and
    /// no-ops correctly on the empty case (custom-dictionary.md). Only Whisper reads them.
    private var customDictionaryTerms: [String] = []

    /// `modelName` is the saved choice; one this Mac can't run falls back to the default
    /// (`runnableModel`). Tests pass a `store` with a temporary folder or a fake loader.
    init(modelName: String = Constants.defaultModel, store: ModelStore = ModelStore()) {
        self.store = store
        let modelName = Self.runnableModel(modelName, macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        // Synchronous disk check: if the model files are already on disk the user
        // will see "Preparing model…" (warm launch); otherwise "Downloading model…" (cold).
        let isCached = store.isDownloaded(modelName)
        selectionSubject = CurrentValueSubject(
            ModelSelection(inUse: modelName, inUseState: isCached ? .loading : .downloading, next: nil))
    }

    // internal for testability — the model a saved choice loads: the choice itself when the
    // catalogue lists it and this macOS runs it, else the default. A name from an older
    // catalogue, or Phonon-2 on macOS 14, has no engine to load it here. Once the default is
    // ready the session saves it as the selected model.
    static func runnableModel(_ name: String, macOSMajor: Int) -> String {
        guard let option = ModelCatalogue.option(named: name), option.minimumMacOS <= macOSMajor
        else { return Constants.defaultModel }
        return name
    }

    private func isDownloaded(_ name: String) -> Bool { store.isDownloaded(name) }

    // internal for testability — drives the load state without touching the real
    // model, so session tests can exercise the model-readiness gate.
    func setModelLoadStateForTesting(_ state: ModelLoadState) {
        update { $0.inUseState = state }
    }

    /// Deletes a downloaded model's files (planning 0038): what `store` names for it, so its
    /// space is freed and choosing it again downloads it. Refuses the model in use, the one
    /// loading beside it, and any model a load is still reading, so a delete never races a
    /// load of the same model. Tests delete from a store with a temporary folder.
    func deleteModel(named name: String) throws {
        guard ModelCatalogue.option(named: name) != nil else { throw ModelDeletionError.notInCatalogue }
        let selection = currentSelection
        guard name != selection.inUse else { throw ModelDeletionError.inUse }
        guard name != selection.next?.target, modelsLoading[name] == nil else { throw ModelDeletionError.loading }
        let fm = FileManager.default
        for folder in store.files(of: name) where fm.fileExists(atPath: folder.path) {
            try fm.removeItem(at: folder)
        }
        logger.info("Deleted model \(name, privacy: .public)")
    }

    /// Idempotent. AppDelegate kicks this off as fire-and-forget at launch.
    /// Coalesces concurrent callers onto the same `Task` so a second `loadModel`
    /// while the first is in-flight doesn't start a second download.
    ///
    /// Emits `ModelLoadState` transitions so the menu bar can show an honest
    /// "Downloading model…" / "Preparing model…" status:
    ///   Cold launch: .downloading → .loading → .ready
    ///   Warm launch: .loading (already set at init) → .ready, offline
    ///   Partial cache: .loading → .downloading → .loading → .ready
    ///   Failure:     .downloading/.loading → .failed
    func loadModel() async throws {
        if model != nil { return }
        if let loadTask {
            _ = try await loadTask.value
            return
        }
        let generation = loadGeneration
        logger.info("Loading model \(self.modelName, privacy: .public)")
        let modelName = self.modelName

        let task = makeLoadTask(modelName: modelName) { [weak self] state in
            // Generation-guarded like the completion paths: a superseded load finishing
            // its download must not mislabel the *newer* switch's published state (e.g.
            // flip "Downloading model…" to "Preparing model…" while another model's
            // download is what the user is actually waiting on).
            if let self, self.loadGeneration == generation {
                self.emitLoadState(state)
            }
        }
        loadTask = task
        do {
            let loaded = try await task.value
            // A model switch bumped the generation while we loaded — the newer
            // `switchModel` owns `model`/state now, so drop this stale result.
            guard generation == loadGeneration else { return }
            model = loaded
            emitLoadState(.ready)
            logger.info("Model loaded")
        } catch {
            // Don't overwrite a newer switch's state with this superseded failure.
            guard generation == loadGeneration else { throw error }
            loadTask = nil
            emitLoadState(.failed)
            logger.error("Model load failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    // A load of `modelName` through `store`, counted in `modelsLoading` from now until
    // it ends, cancelled or not. Shared by the model in use and a staged switch.
    private func makeLoadTask(
        modelName: String, phase: @escaping @MainActor (ModelLoadState) -> Void
    ) -> Task<any LoadedModel, Error> {
        modelsLoading[modelName, default: 0] += 1
        let store = store
        return Task { [weak self] in
            defer {
                if let self {
                    self.modelsLoading[modelName, default: 1] -= 1
                    if self.modelsLoading[modelName] == 0 { self.modelsLoading[modelName] = nil }
                }
            }
            return try await store.load(modelName, phase: phase)
        }
    }

    // Every runtime load-state transition goes through here so on-device incidents
    // (e.g. "the HUD hid while a model was still loading") leave a trace of exactly
    // which state fired and when. State names only — no user content (logging.md).
    private func emitLoadState(_ state: ModelLoadState) {
        logger.info("Model load state -> \(String(describing: state), privacy: .public)")
        update { $0.inUseState = state }
    }

    private func update(_ change: (inout ModelSelection) -> Void) {
        var selection = selectionSubject.value
        change(&selection)
        if selection != selectionSubject.value { selectionSubject.send(selection) }
    }

    // internal for testability — the model picker's current selection, so session
    // tests can confirm a switch actually re-pointed the manager.
    var currentModelName: String { modelName }

    // internal for testability — the synchronous half of a model switch (planning
    // 0021): swaps the model name and resets `model`/`loadTask` so the next
    // `loadModel()` won't early-return, re-entering the 0004 load state
    // (`.downloading` if the new model is uncached, else `.loading`) so the menu bar
    // shows the switch honestly. Returns `false` — a no-op — when the requested model
    // is already active. Split from the async reload so the reset and the state
    // transition are unit-testable on their own.
    @discardableResult
    func prepareModelSwitch(to newModelName: String) -> Bool {
        guard newModelName != modelName else { return false }
        loadGeneration += 1
        model = nil
        loadTask?.cancel()
        loadTask = nil
        dropStagedModel()
        let state: ModelLoadState = isDownloaded(newModelName) ? .loading : .downloading
        logger.info("Model load state -> \(String(describing: state), privacy: .public)")
        update { $0 = ModelSelection(inUse: newModelName, inUseState: state, next: nil) }
        return true
    }

    // internal for testability — when set, `transcribe` returns this string instead of
    // calling the model. Lets session tests exercise post-transcription paths (last-
    // transcript retention, insertion) without a loaded model.
    var transcribeResultForTesting: String?

    /// Chooses a model (planning 0036, Model). Called from `RiverSession` at any time: a
    /// dictation only starts with a ready model, so a choice made during one always loads
    /// beside it and never replaces the model a recording is using.
    /// - While the model in use is ready, the new one loads beside it and the session commits
    ///   the switch once it is ready (`commitModelSwitch`); dictation keeps the current model
    ///   until then.
    /// - With no ready model (the first download, a load still running, or a failed one),
    ///   there is nothing to keep, so the new model replaces the current one at once.
    /// - Choosing the model in use drops a staged switch, or retries the model if it failed.
    /// - A model this Mac can't run is ignored: the Model section never offers one.
    func switchModel(to newModelName: String) async {
        guard Self.runnableModel(newModelName, macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) == newModelName
        else { return }
        if newModelName == modelName {
            if currentModelSwitch != nil {
                dropStagedModel()
            } else if currentModelLoadState == .failed {
                await retryActiveModel()
            }
            return
        }
        guard currentModelLoadState == .ready else {
            guard prepareModelSwitch(to: newModelName) else { return }
            try? await loadModel()
            return
        }
        if let current = currentModelSwitch, current.target == newModelName, current.phase != .failed { return }
        await stage(newModelName)
    }

    /// Makes the staged model the one in use. Returns `false` unless a switch is `.ready`.
    /// The session calls this only at `.idle`, so no recording ever changes model halfway.
    @discardableResult
    func commitModelSwitch() -> Bool {
        guard let pending = currentModelSwitch, pending.phase == .ready else { return false }
        loadGeneration += 1
        model = staged
        staged = nil
        stagedTask = nil
        loadTask = nil
        update { $0 = ModelSelection(inUse: pending.target, inUseState: .ready, next: nil) }
        logger.info("Switched to model \(pending.target, privacy: .public)")
        return true
    }

    private func stage(_ target: String) async {
        dropStagedModel()
        let generation = stageGeneration
        update { $0.next = ModelSwitch(target: target, phase: isDownloaded(target) ? .preparing : .downloading) }
        logger.info("Loading model \(target, privacy: .public) beside the one in use")
        let task = makeLoadTask(modelName: target) { [weak self] state in
            guard let self, self.stageGeneration == generation else { return }
            self.update { $0.next = ModelSwitch(target: target, phase: state == .downloading ? .downloading : .preparing) }
        }
        stagedTask = task
        do {
            let loaded = try await task.value
            guard generation == stageGeneration else { return }
            staged = loaded
            update { $0.next = ModelSwitch(target: target, phase: .ready) }
        } catch {
            guard generation == stageGeneration else { return }
            stagedTask = nil
            update { $0.next = ModelSwitch(target: target, phase: .failed) }
            logger.error("Staged model load failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
        }
    }

    // Cancels any staged load and forgets its result; the model in use is untouched.
    private func dropStagedModel() {
        stageGeneration += 1
        stagedTask?.cancel()
        stagedTask = nil
        staged = nil
        update { $0.next = nil }
    }

    // A failed model chosen again loads from the start: the failed load left no task to join.
    private func retryActiveModel() async {
        loadGeneration += 1
        model = nil
        loadTask = nil
        emitLoadState(isDownloaded(modelName) ? .loading : .downloading)
        try? await loadModel()
    }

    func setCustomDictionaryTerms(_ terms: [String]) {
        customDictionaryTerms = terms
    }

    // internal for the manual A/B eval harness (`DictionaryEvalTests`) — NOT used in
    // production. The dictionary prompt is Whisper's, so this needs a loaded Whisper model.
    func evaluateDictionaryPrompt(wavPath: String) async throws -> (promptTokenCount: Int, off: String, on: String) {
        guard let whisper = model as? WhisperKitModel else { throw TranscriptionError.modelNotLoaded }
        return try await whisper.evaluateDictionaryPrompt(wavPath: wavPath, dictionaryTerms: customDictionaryTerms)
    }

    /// Returns the transcribed text or throws. Throws `.modelNotLoaded` if
    /// `loadModel` hasn't completed (the fail-fast surface — the session logs
    /// and still returns the cycle to `.idle`).
    func transcribe(audioSamples: [Float]) async throws -> String {
        if let result = transcribeResultForTesting { return result }
        guard let model else { throw TranscriptionError.modelNotLoaded }
        logger.info("Transcribing \(audioSamples.count, privacy: .public) samples with \(self.modelName, privacy: .public)")
        let text = try await model.transcribe(Self.paddedForDecoding(audioSamples), dictionaryTerms: customDictionaryTerms)
        logger.info("Transcribed \(text.count, privacy: .public) chars")
        return text
    }

    // internal for testability — a clip under `shortClipSeconds` gets silence on each side,
    // the context Whisper needs to hear a short word at all; longer clips decode as captured.
    // Every engine gets it: it also lifts any clip past FluidAudio's 0.3 s minimum, which a
    // shorter clip would fail.
    nonisolated static func paddedForDecoding(_ samples: [Float], sampleRate: Double = 16_000) -> [Float] {
        guard !samples.isEmpty, Double(samples.count) < Constants.shortClipSeconds * sampleRate else { return samples }
        let silence = [Float](repeating: 0, count: Int(Constants.shortClipPadSeconds * sampleRate))
        return silence + samples + silence
    }
}
