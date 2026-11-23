import Foundation
import WhisperKit
import os

private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "transcribe")

/// The Whisper models' loader: the only file that imports WhisperKit (planning 0037).
struct WhisperKitLoader: ModelLoader {
    // Where WhisperKit puts a model's CoreML files:
    // {base}/models/argmaxinc/whisperkit-coreml/{name}/. Pure (no I/O).
    func folder(of model: String, downloadBase: URL) -> URL {
        Self.modelFolder(downloadBase: downloadBase, modelName: model)
    }

    /// The model's folder and its download records, which Delete removes (planning 0038). The
    /// tokenizer folders under `models/openai` stay: they are small and shared between models.
    func files(of model: String, downloadBase: URL) -> [URL] {
        [Self.modelFolder(downloadBase: downloadBase, modelName: model),
         Self.downloadRecordsFolder(downloadBase: downloadBase, modelName: model)]
    }

    func isDownloaded(_ model: String, downloadBase: URL) -> Bool {
        Self.isModelCached(downloadBase: downloadBase, modelName: model)
    }

    func load(
        _ model: String, downloadBase: URL, phase: @escaping @MainActor (ModelLoadState) -> Void,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> any LoadedModel {
        WhisperKitModel(try await Self.makeWhisperKit(
            modelName: model, downloadBase: downloadBase, phase: phase, progress: progress))
    }

    nonisolated static func modelFolder(downloadBase: URL, modelName: String) -> URL {
        downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(modelName)", isDirectory: true)
    }

    // The Hub's download records for a model: a `.metadata` file per downloaded file, and a
    // cut-off file's `.incomplete` part, which a later download resumes from.
    nonisolated private static func downloadRecordsFolder(downloadBase: URL, modelName: String) -> URL {
        downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/\(modelName)", isDirectory: true)
    }

    // The files each compiled Core ML model in a WhisperKit model folder holds, as
    // `argmaxinc/whisperkit-coreml` ships them.
    private static let compiledModelFiles = [
        "coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin", "analytics/coremldata.bin",
    ]

    // internal for testability — whether the model's full file set is on disk (planning
    // 0026, finding 3; 0038). Used at init time to set the initial load state (downloading
    // vs. loading) without an async call, by `load` to load a cached model offline, and
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

    // swift-transformers reads the key as `tokenizerClass` or `tokenizer_class` and
    // needs a string value; anything else sends it to the fallback lookup.
    private static func namesTokenizerClass(_ tokenizerConfig: URL) -> Bool {
        guard let data = try? Data(contentsOf: tokenizerConfig),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return (json["tokenizerClass"] ?? json["tokenizer_class"]) is String
    }

    // Downloads the model if it is not cached, then loads it. `phase` hears `.downloading` when
    // a cached folder won't load and the download path takes over, and `.loading` once the
    // files are on disk; `progress` hears the download's fraction while it runs.
    private static func makeWhisperKit(
        modelName: String, downloadBase: URL, phase: @escaping @MainActor (ModelLoadState) -> Void,
        progress: @escaping @MainActor (Double) -> Void
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
                phase(.downloading)
            }
        }
        // Phase 1: download or find cached model files. `load: false` skips the
        // in-memory load so we can emit the `.loading` transition before it.
        let wk = try await whileDownloading(modelName, downloadBase: downloadBase, progress: progress) {
            try await WhisperKit(model: modelName, downloadBase: downloadBase, load: false)
        }
        // Phase 2: files confirmed on disk — now loading CoreML models into memory.
        phase(.loading)
        // Again after the download, which can add files to the model folder.
        try checkTokenizerFiles(downloadBase: downloadBase, modelName: modelName)
        try await wk.loadModels()
        return wk
    }

    // Runs `download` while a task off the main actor measures the model's bytes on disk every
    // half second and reports them against the catalogue's size (planning 0004). WhisperKit's
    // own progress counts files, and two weight files hold nearly all of a model, so it jumps.
    private static func whileDownloading<T>(
        _ modelName: String, downloadBase: URL, progress: @escaping @MainActor (Double) -> Void,
        _ download: () async throws -> T
    ) async throws -> T {
        let megabytes = ModelCatalogue.option(named: modelName)?.downloadMegabytes ?? 0
        let folders = downloadFolders(downloadBase: downloadBase, modelName: modelName)
        let sampler = Task.detached(priority: .utility) {
            let throttle = DownloadProgressThrottle()
            while !Task.isCancelled {
                let bytes = bytesOnDisk(in: folders)
                if let fraction = throttle.report(downloadFraction(bytes: bytes, megabytes: megabytes)) {
                    await progress(fraction)
                }
                try? await Task.sleep(for: .seconds(Constants.downloadProgressSampleSeconds))
            }
        }
        defer { sampler.cancel() }
        return try await download()
    }

    // internal for testability — where a download's bytes are while it runs: the files already
    // whole in the model's folder, and the part of each file still coming in, which the Hub
    // writes as an `.incomplete` file among the download records and moves in once it is whole.
    nonisolated static func downloadFolders(downloadBase: URL, modelName: String) -> [URL] {
        [modelFolder(downloadBase: downloadBase, modelName: modelName),
         downloadRecordsFolder(downloadBase: downloadBase, modelName: modelName)]
    }

    // internal for testability — the bytes in `folders` as Finder counts them.
    nonisolated static func bytesOnDisk(in folders: [URL]) -> Int64 {
        folders.compactMap(ModelStore.diskUsage(of:)).reduce(0, +)
    }

    // internal for testability — a download's fraction from its bytes on disk and the
    // catalogue's size. It stops short of 1 (`downloadProgressCeiling`): the size is a
    // measurement, so only the end of the download says it is done.
    nonisolated static func downloadFraction(bytes: Int64, megabytes: Int) -> Double {
        guard megabytes > 0 else { return 0 }
        return min(Double(bytes) / (Double(megabytes) * 1_000_000), Constants.downloadProgressCeiling)
    }

    // internal for the eval harness (`TranscriptionEvalTests`, planning 0022) —
    // loads a clip to the 16 kHz float array River transcribes. Wraps
    // `AudioProcessor` so WhisperKit stays a single import boundary and the test
    // target need not depend on it. Not used in production (live capture supplies
    // samples directly).
    static func loadAudioSamples(fromPath path: String) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
    }
}

/// A loaded Whisper model: the custom-dictionary prompt, its retry without the prompt, and the
/// non-speech annotation check are Whisper's (planning 0037). Whisper reads 30 s at a time, and
/// WhisperKit steps through longer audio itself (planning 0039).
@MainActor
final class WhisperKitModel: LoadedModel {
    private let whisperKit: WhisperKit

    init(_ whisperKit: WhisperKit) { self.whisperKit = whisperKit }

    func transcribe(_ samples: [Float], dictionaryTerms: [String]) async throws -> String? {
        let padded = ShortClip.padded(samples)
        let promptTokens = buildPromptTokens(dictionaryTerms)
        return try await Self.resolveWithEmptyPromptRetry(promptTokens: promptTokens) { tokens in
            try await self.decode(padded, promptTokens: tokens)
        }
    }

    // internal for testability — the "a custom-dictionary prompt must only ever
    // *help*" retry rule, lifted out of `transcribe` as a narrow decode seam so
    // it runs without a live model. The caller injects a `decode` closure (the
    // real WhisperKit call in production, a canned string in tests).
    //
    // A small model like `base.en` can occasionally emit empty output when
    // conditioned on a prompt; without the retry, adding a dictionary term could
    // turn a working dictation into nothing said — strictly worse than no
    // dictionary (requirements/custom-dictionary.md). Retry unprompted so the
    // dictionary degrades to neutral. Empty or annotation-only output
    // ("[BLANK_AUDIO]") is how Whisper hears no speech: nil, as for every engine
    // (planning 0039). Logged so prompt-quality regressions stay observable.
    static func resolveWithEmptyPromptRetry(
        promptTokens: [Int],
        decode: (_ promptTokens: [Int]) async throws -> String
    ) async throws -> String? {
        var text = try await decode(promptTokens)
        if text.isEmpty || isNonSpeechAnnotation(text), !promptTokens.isEmpty {
            logger.warning("Prompted transcription had no speech; retrying without the custom-dictionary prompt")
            text = try await decode([])
        }
        return text.isEmpty || isNonSpeechAnnotation(text) ? nil : text
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
    nonisolated static func isNonSpeechAnnotation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let stripped = trimmed
            .replacingOccurrences(of: #"\[[^\[\]]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\([^()]*\)"#, with: "", options: .regularExpression)
        guard stripped != trimmed else { return false }  // no annotation present at all
        return stripped.allSatisfy { $0.isPunctuation || $0.isWhitespace }
    }

    private func decode(_ audioSamples: [Float], promptTokens: [Int]) async throws -> String {
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
    // in production. Loads one fixed clip and decodes it twice: with the
    // custom-dictionary prompt and without, **bypassing** `transcribe`'s empty
    // fallback, so the harness can see whether the prompt degenerates (empty) or
    // actually biases the output. The clip is the only thing held constant; the
    // prompt is the only variable.
    func evaluateDictionaryPrompt(wavPath: String, dictionaryTerms: [String]) async throws -> (promptTokenCount: Int, off: String, on: String) {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: wavPath)
        let promptTokens = buildPromptTokens(dictionaryTerms)
        let off = try await decode(samples, promptTokens: [])
        let on = try await decode(samples, promptTokens: promptTokens)
        return (promptTokens.count, off, on)
    }

    private func buildPromptTokens(_ terms: [String]) -> [Int] {
        guard !terms.isEmpty, let tokenizer = whisperKit.tokenizer else { return [] }
        let prompt = " " + terms.joined(separator: ", ")
        let raw = tokenizer.encode(text: prompt)
        return Self.filterSpecialTokens(raw, specialTokenBegin: tokenizer.specialTokens.specialTokenBegin)
    }

    // internal for testability — the load-bearing custom-dictionary filter.
    // Tokens at or above `specialTokenBegin` are timestamp / language / sentinel
    // tokens; injecting them into `promptTokens` silently corrupts decoding
    // (custom-dictionary.md). Pure function, exercised on synthetic inputs.
    nonisolated static func filterSpecialTokens(_ tokens: [Int], specialTokenBegin: Int) -> [Int] {
        tokens.filter { $0 < specialTokenBegin }
    }
}
