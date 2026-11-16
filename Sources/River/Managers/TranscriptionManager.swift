import Combine
import Foundation
import WhisperKit
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
    /// WhisperKit returned no text for a non-empty audio buffer. Distinct from
    /// the no-audio path (`AudioCaptureError.noAudioCaptured` in M5) so the
    /// log shows *what* failed.
    case emptyTranscription
    /// Decode produced only non-speech annotations (`[BLANK_AUDIO]`, `(heavy
    /// breathing)`, …): Whisper heard the audio but found no words in it. The
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

    private var whisperKit: WhisperKit?
    private var loadTask: Task<WhisperKit, Error>?
    // Bumped by every `prepareModelSwitch`; a `loadModel` run only commits its result
    // when its captured generation is still current, so a switch that supersedes an
    // in-flight load (e.g. the launch load) can't clobber the newer model's state.
    private var loadGeneration = 0

    // The next model, loading beside the one in use. Its own generation, so a newer
    // choice drops an older staged load's result.
    private var staged: WhisperKit?
    private var stagedTask: Task<WhisperKit, Error>?
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
    /// no-ops correctly on the empty case (custom-dictionary.md).
    private var customDictionaryTerms: [String] = []

    init(modelName: String = Constants.defaultModel) {
        // Synchronous disk check: if the model files are already on disk the user
        // will see "Preparing model…" (warm launch); otherwise "Downloading model…" (cold).
        let downloadBase = Self.modelDownloadBase()
        let isCached = Self.isModelCached(downloadBase: downloadBase, modelName: modelName)
        selectionSubject = CurrentValueSubject(
            ModelSelection(inUse: modelName, inUseState: isCached ? .loading : .downloading, next: nil))
    }

    // internal for testability — drives the load state without touching the real
    // model, so session tests can exercise the model-readiness gate.
    func setModelLoadStateForTesting(_ state: ModelLoadState) {
        update { $0.inUseState = state }
    }

    // internal for testability — the model download root. Application Support
    // (not WhisperKit's ~/Documents default) so model downloads never trip the
    // Documents-folder TCC prompt (planning 0010). Pure (no I/O); `loadModel`
    // creates the directory.
    static func modelDownloadBase() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Constants.modelCacheFolderName, isDirectory: true)
    }

    // Where WhisperKit puts a model's CoreML files:
    // {base}/models/argmaxinc/whisperkit-coreml/{name}/. Pure (no I/O). Internal so the
    // Model section can show a model's folder in Finder.
    static func modelFolder(downloadBase: URL, modelName: String) -> URL {
        downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(modelName)", isDirectory: true)
    }

    // The files each compiled Core ML model in a WhisperKit model folder holds, as
    // `argmaxinc/whisperkit-coreml` ships them.
    private static let compiledModelFiles = [
        "coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin", "analytics/coremldata.bin",
    ]

    // internal for testability — whether the model's full file set is on disk (planning
    // 0026, finding 3; 0038). Used at init time to set the initial load state (downloading
    // vs. loading) without an async call, by `loadModel` to load a cached model offline, and
    // by the Model section for "Downloaded" and Delete. The Hub downloads each file beside
    // the folder and moves it in only once it is whole, so a cut-off download shows as
    // missing files, never as a short one: checking that every file is present is enough.
    // The three models WhisperKit requires must be complete, and the prefill model too when
    // its folder exists, since WhisperKit then loads it.
    static func isModelCached(downloadBase: URL, modelName: String) -> Bool {
        let dir = modelFolder(downloadBase: downloadBase, modelName: modelName)
        let fm = FileManager.default
        func exists(_ path: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(path).path) }
        func complete(_ model: String) -> Bool { compiledModelFiles.allSatisfy { exists("\(model).mlmodelc/\($0)") } }
        return exists("config.json") && exists("generation_config.json")
            && ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy(complete)
            && (!exists("TextDecoderContextPrefill.mlmodelc") || complete("TextDecoderContextPrefill"))
    }

    // internal for testability — throws `.unusableTokenizerConfig` when a folder
    // WhisperKit could load the tokenizer from would crash the app. WhisperKit 0.18.0
    // takes the first of these with a `tokenizer.json`: {base}/models/openai/whisper-{variant},
    // {base}, the model folder, {model folder}/models/openai/whisper-{variant}. If that
    // folder has a `config.json` but its `tokenizer_config.json` is missing or names no
    // `tokenizer_class`, swift-transformers looks for a fallback config in its `Hub`
    // resource bundle, which River.app does not carry, and the missing bundle is a
    // `fatalError`. A tokenizer download cut off before `tokenizer_config.json` leaves
    // that state. The variant is known only after the CoreML load, so every
    // `whisper-*` folder is checked. Pure file reads, no network.
    static func checkTokenizerFiles(downloadBase: URL, modelName: String) throws {
        let fm = FileManager.default
        let model = modelFolder(downloadBase: downloadBase, modelName: modelName)
        func tokenizerRepos(under base: URL) -> [URL] {
            let dir = base.appendingPathComponent("models/openai", isDirectory: true)
            return (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }
        let candidates = tokenizerRepos(under: downloadBase) + [downloadBase, model] + tokenizerRepos(under: model)
        for folder in candidates
        where fm.fileExists(atPath: folder.appendingPathComponent("tokenizer.json").path)
            && fm.fileExists(atPath: folder.appendingPathComponent("config.json").path)
            && !namesTokenizerClass(folder.appendingPathComponent("tokenizer_config.json")) {
            throw TranscriptionError.unusableTokenizerConfig(folderName: folder.lastPathComponent)
        }
    }

    /// The folder every model's files live in: what the Model section names and shows in Finder.
    static func modelsFolder(downloadBase: URL) -> URL {
        downloadBase.appendingPathComponent("models", isDirectory: true)
    }

    // The Hub's download records for a model: a `.metadata` file per downloaded file, and a
    // cut-off file's `.incomplete` part, which a later download resumes from.
    private static func downloadRecordsFolder(downloadBase: URL, modelName: String) -> URL {
        downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/\(modelName)", isDirectory: true)
    }

    /// The space `url` takes on disk, as Finder counts it: the blocks allocated to every file
    /// under it, in bytes. `nil` when nothing is there.
    static func diskUsage(of url: URL) -> Int64? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        func size(_ file: URL) -> Int64 {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return 0 }
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
        guard let files = fm.enumerator(at: url, includingPropertiesForKeys: keys) else { return size(url) }
        return files.reduce(size(url)) { total, file in total + ((file as? URL).map(size) ?? 0) }
    }

    /// What deleting `modelName` frees: its folder and its download records.
    static func diskUsage(downloadBase: URL, modelName: String) -> Int64 {
        [modelFolder(downloadBase: downloadBase, modelName: modelName),
         downloadRecordsFolder(downloadBase: downloadBase, modelName: modelName)]
            .compactMap(diskUsage(of:)).reduce(0, +)
    }

    /// Deletes a downloaded model's folder and its download records (planning 0038), so its
    /// space is freed and choosing it again downloads it. The tokenizer folders under
    /// `models/openai` stay: they are small and shared between models. Refuses the model in
    /// use, the one loading beside it, and any model a load is still reading, so a delete
    /// never races a load of the same model. `downloadBase` is a parameter so tests delete
    /// from a temporary folder.
    func deleteModel(named name: String, downloadBase: URL) throws {
        guard Constants.curatedModels.contains(where: { $0.name == name }) else { throw ModelDeletionError.notInCatalogue }
        let selection = currentSelection
        guard name != selection.inUse else { throw ModelDeletionError.inUse }
        guard name != selection.next?.target, modelsLoading[name] == nil else { throw ModelDeletionError.loading }
        let fm = FileManager.default
        for folder in [Self.modelFolder(downloadBase: downloadBase, modelName: name),
                       Self.downloadRecordsFolder(downloadBase: downloadBase, modelName: name)]
        where fm.fileExists(atPath: folder.path) {
            try fm.removeItem(at: folder)
        }
        logger.info("Deleted model \(name, privacy: .public)")
    }

    // swift-transformers reads the key as `tokenizerClass` or `tokenizer_class` and
    // needs a string value; anything else sends it to the fallback lookup.
    private static func namesTokenizerClass(_ tokenizerConfig: URL) -> Bool {
        guard let data = try? Data(contentsOf: tokenizerConfig),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return (json["tokenizerClass"] ?? json["tokenizer_class"]) is String
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
        if whisperKit != nil { return }
        if let loadTask {
            _ = try await loadTask.value
            return
        }
        let generation = loadGeneration
        logger.info("Loading WhisperKit model \(self.modelName, privacy: .public)")
        let downloadBase = Self.modelDownloadBase()
        let modelName = self.modelName

        let task = makeLoadTask(modelName: modelName, downloadBase: downloadBase) { [weak self] state in
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
            let wk = try await task.value
            // A model switch bumped the generation while we loaded — the newer
            // `switchModel` owns `whisperKit`/state now, so drop this stale result.
            guard generation == loadGeneration else { return }
            whisperKit = wk
            emitLoadState(.ready)
            logger.info("WhisperKit model loaded")
        } catch {
            // Don't overwrite a newer switch's state with this superseded failure.
            guard generation == loadGeneration else { throw error }
            loadTask = nil
            emitLoadState(.failed)
            logger.error("WhisperKit load failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            throw error
        }
    }

    // A load of `modelName`, counted in `modelsLoading` from now until it ends, cancelled or not.
    private func makeLoadTask(
        modelName: String, downloadBase: URL, phase: @escaping @MainActor (ModelLoadState) -> Void
    ) -> Task<WhisperKit, Error> {
        modelsLoading[modelName, default: 0] += 1
        return Task { [weak self, logger] in
            defer {
                if let self {
                    self.modelsLoading[modelName, default: 1] -= 1
                    if self.modelsLoading[modelName] == 0 { self.modelsLoading[modelName] = nil }
                }
            }
            return try await Self.makeWhisperKit(modelName: modelName, downloadBase: downloadBase, logger: logger, phase: phase)
        }
    }

    // Downloads the model if it is not cached, then loads it. `phase` hears `.downloading` when
    // a cached folder won't load and the download path takes over, and `.loading` once the
    // files are on disk. Shared by the model in use and a staged switch.
    private static func makeWhisperKit(
        modelName: String, downloadBase: URL, logger: Logger, phase: @escaping @MainActor (ModelLoadState) -> Void
    ) async throws -> WhisperKit {
        // Download under Application Support (planning 0010).
        try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
        // An unusable tokenizer folder fails the load here rather than crash it.
        // Outside the cached branch's catch: a fresh download does not repair it.
        try checkTokenizerFiles(downloadBase: downloadBase, modelName: modelName)
        // A cached model loads straight from its folder with downloading off: no
        // network, so a warm launch is quick and works offline. WhisperKit's
        // download path asks Hugging Face for the file list first, even when every
        // file is on disk (planning 0004 follow-up). A partial download fails the
        // cache check (planning 0026) and takes the download path, which completes
        // it; if a complete-looking folder still won't load, fall through to it too.
        if isModelCached(downloadBase: downloadBase, modelName: modelName) {
            do {
                let folder = modelFolder(downloadBase: downloadBase, modelName: modelName)
                let wk = try await WhisperKit(
                    model: modelName, downloadBase: downloadBase, modelFolder: folder.path,
                    load: false, download: false
                )
                try await wk.loadModels()
                return wk
            } catch {
                try Task.checkCancellation()
                logger.warning("Cached model failed to load, downloading it again: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
                await phase(.downloading)
            }
        }
        // Phase 1: download or find cached model files. `load: false` skips the
        // in-memory load so we can emit the `.loading` transition before it.
        let wk = try await WhisperKit(model: modelName, downloadBase: downloadBase, load: false)
        // Phase 2: files confirmed on disk — now loading CoreML models into memory.
        await phase(.loading)
        // Again after the download, which can add files to the model folder.
        try checkTokenizerFiles(downloadBase: downloadBase, modelName: modelName)
        try await wk.loadModels()
        return wk
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
    // 0021): swaps the model name and resets `whisperKit`/`loadTask` so the next
    // `loadModel()` won't early-return, re-entering the 0004 load state
    // (`.downloading` if the new model is uncached, else `.loading`) so the menu bar
    // shows the switch honestly. Returns `false` — a no-op — when the requested model
    // is already active. Split from the async reload so the reset and the state
    // transition are unit-testable without loading a real WhisperKit model.
    @discardableResult
    func prepareModelSwitch(to newModelName: String) -> Bool {
        guard newModelName != modelName else { return false }
        loadGeneration += 1
        whisperKit = nil
        loadTask?.cancel()
        loadTask = nil
        dropStagedModel()
        let isCached = Self.isModelCached(downloadBase: Self.modelDownloadBase(), modelName: newModelName)
        let state: ModelLoadState = isCached ? .loading : .downloading
        logger.info("Model load state -> \(String(describing: state), privacy: .public)")
        update { $0 = ModelSelection(inUse: newModelName, inUseState: state, next: nil) }
        return true
    }

    // internal for testability — turns the async reload half of `switchModel` into a
    // no-op so `RiverSession` tests can exercise the apply-or-defer routing without
    // loading a real WhisperKit model (mirrors `MicrophoneCapability.skipEngineForTesting`).
    // The synchronous `prepareModelSwitch` still runs, so the re-point and the
    // load-state transition stay observable.
    var skipLoadForTesting = false

    // internal for testability — when set, `transcribe` returns this string instead of
    // calling WhisperKit. Lets session tests exercise post-transcription paths (last-
    // transcript retention, insertion) without a live model.
    var transcribeResultForTesting: String?

    // internal for testability — with `skipLoadForTesting`, how a staged load ends: success
    // marks the switch `.ready` with no real model behind it, so the session's commit path
    // runs without a WhisperKit download.
    var stageFailsForTesting = false

    /// Chooses a model (planning 0036, Model). Called from `RiverSession` at any time: a
    /// dictation only starts with a ready model, so a choice made during one always loads
    /// beside it and never replaces the model a recording is using.
    /// - While the model in use is ready, the new one loads beside it and the session commits
    ///   the switch once it is ready (`commitModelSwitch`); dictation keeps the current model
    ///   until then.
    /// - With no ready model (the first download, a load still running, or a failed one),
    ///   there is nothing to keep, so the new model replaces the current one at once.
    /// - Choosing the model in use drops a staged switch, or retries the model if it failed.
    func switchModel(to newModelName: String) async {
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
            if skipLoadForTesting { return }
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
        whisperKit = staged
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
        let downloadBase = Self.modelDownloadBase()
        let isCached = Self.isModelCached(downloadBase: downloadBase, modelName: target)
        update { $0.next = ModelSwitch(target: target, phase: isCached ? .preparing : .downloading) }
        logger.info("Loading model \(target, privacy: .public) beside the one in use")
        if skipLoadForTesting {
            update { $0.next = ModelSwitch(target: target, phase: stageFailsForTesting ? .failed : .ready) }
            return
        }
        let task = makeLoadTask(modelName: target, downloadBase: downloadBase) { [weak self] state in
            guard let self, self.stageGeneration == generation else { return }
            self.update { $0.next = ModelSwitch(target: target, phase: state == .downloading ? .downloading : .preparing) }
        }
        stagedTask = task
        do {
            let wk = try await task.value
            guard generation == stageGeneration else { return }
            staged = wk
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
        whisperKit = nil
        loadTask = nil
        let isCached = Self.isModelCached(downloadBase: Self.modelDownloadBase(), modelName: modelName)
        emitLoadState(isCached ? .loading : .downloading)
        if skipLoadForTesting { return }
        try? await loadModel()
    }

    func setCustomDictionaryTerms(_ terms: [String]) {
        customDictionaryTerms = terms
    }

    // internal for the eval harness (`TranscriptionEvalTests`, planning 0022) —
    // loads a clip to the 16 kHz float array WhisperKit decodes. Wraps
    // `AudioProcessor` so WhisperKit stays a single import boundary and the test
    // target need not depend on it. Not used in production (live capture supplies
    // samples directly).
    static func loadAudioSamples(fromPath path: String) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
    }

    /// Returns the transcribed text or throws. Throws `.modelNotLoaded` if
    /// `loadModel` hasn't completed (the fail-fast surface — the session logs
    /// and still returns the cycle to `.idle`).
    func transcribe(audioSamples: [Float]) async throws -> String {
        if let result = transcribeResultForTesting { return result }
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        logger.info("Transcribing \(audioSamples.count, privacy: .public) samples")

        let promptTokens = buildPromptTokens(using: whisperKit)
        let samples = Self.paddedForDecoding(audioSamples)
        let text = try await resolveWithEmptyPromptRetry(promptTokens: promptTokens) { tokens in
            try await self.decode(samples, promptTokens: tokens, using: whisperKit)
        }
        logger.info("Transcribed \(text.count, privacy: .public) chars")
        return text
    }

    // internal for testability — a clip under `shortClipSeconds` gets silence on each side,
    // the context Whisper needs to hear a short word at all; longer clips decode as captured.
    nonisolated static func paddedForDecoding(_ samples: [Float], sampleRate: Double = 16_000) -> [Float] {
        guard !samples.isEmpty, Double(samples.count) < Constants.shortClipSeconds * sampleRate else { return samples }
        let silence = [Float](repeating: 0, count: Int(Constants.shortClipPadSeconds * sampleRate))
        return silence + samples + silence
    }

    // internal for testability — the "a custom-dictionary prompt must only ever
    // *help*" retry rule, lifted out of `transcribe` as a narrow decode seam so
    // it runs without a live model. This is ADR 0001's named-but-unpromoted seam,
    // NOT a `Transcriber` protocol: the caller injects a `decode` closure (the
    // real WhisperKit call in production, a canned string in tests).
    //
    // A small model like `base.en` can occasionally emit empty output when
    // conditioned on a prompt; without the retry, adding a dictionary term could
    // turn a working dictation into a hard `.emptyTranscription` — strictly worse
    // than no dictionary (requirements/custom-dictionary.md). Retry unprompted so
    // the dictionary degrades to neutral. Annotation-only output ("[BLANK_AUDIO]")
    // counts as no-speech for the retry, and classifies as `.noSpeechDetected`
    // at the end (vs `.emptyTranscription` for a truly empty decode — the session
    // treats the former as a quiet no-op and the latter as a loud failure).
    // Logged so prompt-quality regressions stay observable.
    func resolveWithEmptyPromptRetry(
        promptTokens: [Int],
        decode: (_ promptTokens: [Int]) async throws -> String
    ) async throws -> String {
        var text = try await decode(promptTokens)
        if text.isEmpty || Self.isNonSpeechAnnotation(text), !promptTokens.isEmpty {
            logger.warning("Prompted transcription had no speech; retrying without the custom-dictionary prompt")
            text = try await decode([])
        }
        guard !text.isEmpty else { throw TranscriptionError.emptyTranscription }
        guard !Self.isNonSpeechAnnotation(text) else { throw TranscriptionError.noSpeechDetected }
        return text
    }

    // internal for testability — true when decoded text consists *only* of
    // Whisper's non-speech annotations: bracketed or parenthesized labels like
    // "[BLANK_AUDIO]", "[MUSIC]", "(heavy breathing)", plus any leftover
    // punctuation. The decode gates (`noSpeechThreshold` etc.) do not reliably
    // suppress these — probed on-device with real quiet-room/breath/keyboard
    // clips (planning 0023) — so without this check they paste as literal text.
    // Whole-output classification only: mixed annotation+speech output is left
    // untouched, so dictation that legitimately contains brackets never loses
    // content.
    static func isNonSpeechAnnotation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let stripped = trimmed
            .replacingOccurrences(of: #"\[[^\[\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\([^()]*\)"#, with: "", options: .regularExpression)
        guard stripped != trimmed else { return false }  // no annotation present at all
        return stripped.allSatisfy { $0.isPunctuation || $0.isWhitespace }
    }

    private func decode(_ audioSamples: [Float], promptTokens: [Int], using whisperKit: WhisperKit) async throws -> String {
        // Pin the no-speech / log-prob gate and the temperature-fallback schedule
        // to upstream Whisper defaults (planning 0023). WhisperKit 0.18 already
        // defaults to these, but setting them explicitly keeps the gate from
        // silently regressing if an upstream default changes. Values live in
        // `Constants`, not settings — the user shouldn't reason about them.
        let options = DecodingOptions(
            temperature: Constants.decodingTemperature,
            temperatureIncrementOnFallback: Constants.decodingTemperatureIncrementOnFallback,
            temperatureFallbackCount: Constants.decodingTemperatureFallbackCount,
            promptTokens: promptTokens.isEmpty ? nil : promptTokens,
            compressionRatioThreshold: Constants.compressionRatioThreshold,
            logProbThreshold: Constants.logProbThreshold,
            noSpeechThreshold: Constants.noSpeechThreshold
        )
        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)
        } catch {
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // internal for the manual A/B eval harness (`DictionaryEvalTests`) — NOT used
    // in production. Loads one fixed clip and decodes it twice: with the current
    // custom-dictionary prompt and without, **bypassing** `transcribe`'s empty
    // fallback, so the harness can see whether the prompt degenerates (empty) or
    // actually biases the output. The clip is the only thing held constant; the
    // prompt is the only variable.
    func evaluateDictionaryPrompt(wavPath: String) async throws -> (promptTokenCount: Int, off: String, on: String) {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: wavPath)
        guard let whisperKit else { throw TranscriptionError.modelNotLoaded }
        let promptTokens = buildPromptTokens(using: whisperKit)
        let off = try await decode(samples, promptTokens: [], using: whisperKit)
        let on = try await decode(samples, promptTokens: promptTokens, using: whisperKit)
        return (promptTokens.count, off, on)
    }

    private func buildPromptTokens(using whisperKit: WhisperKit) -> [Int] {
        guard !customDictionaryTerms.isEmpty, let tokenizer = whisperKit.tokenizer else { return [] }
        let prompt = " " + customDictionaryTerms.joined(separator: ", ")
        let raw = tokenizer.encode(text: prompt)
        return Self.filterSpecialTokens(raw, specialTokenBegin: tokenizer.specialTokens.specialTokenBegin)
    }

    // internal for testability — the load-bearing custom-dictionary filter.
    // Tokens at or above `specialTokenBegin` are timestamp / language / sentinel
    // tokens; injecting them into `promptTokens` silently corrupts decoding
    // (custom-dictionary.md). Pure function, exercised on synthetic inputs.
    static func filterSpecialTokens(_ tokens: [Int], specialTokenBegin: Int) -> [Int] {
        tokens.filter { $0 < specialTokenBegin }
    }
}
