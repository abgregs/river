import FluidAudio
import Foundation
import os

private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "transcribe")

/// The Parakeet and Phonon models' loader: the only file that imports FluidAudio (planning
/// 0037). A model's name is its FluidAudio repo, kept in River's one models folder (planning
/// 0038) under `models/FluidInference`, so the Model section's folder total, Show in Finder
/// and Delete cover it like a Whisper model.
struct FluidAudioLoader: ModelLoader {
    // internal for testability — the FluidAudio 0.18.3 version and repo for each model River
    // lists. `AsrModelVersion.repo` is internal to FluidAudio, so River pairs them itself, and
    // the catalogue can't hold FluidAudio's types without importing it: a test checks that
    // every FluidAudio model in the catalogue is here.
    static let models: [String: (version: AsrModelVersion, repo: Repo)] = [
        "parakeet-tdt-0.6b-v2-coreml": (.v2, .parakeetV2),
        "phonon-2-coreml": (.phonon2, .phonon2),
    ]

    /// Where FluidAudio writes the model: its repo's `folderName`, which drops the repo name's
    /// "-coreml" (`phonon-2`), under the folder River hands it.
    func folder(of model: String, downloadBase: URL) -> URL {
        let folderName = Self.models[model]?.repo.folderName ?? model
        return downloadBase.appendingPathComponent("models/FluidInference/\(folderName)", isDirectory: true)
    }

    /// FluidAudio's own load-ready check: every compiled model complete and the vocabulary
    /// present. A cut-off download leaves `.partial` files inside the folder, which fail it.
    func isDownloaded(_ model: String, downloadBase: URL) -> Bool {
        guard let version = Self.models[model]?.version else { return false }
        return AsrModels.modelsExist(at: folder(of: model, downloadBase: downloadBase), version: version)
    }

    func load(
        _ model: String, downloadBase: URL, phase: @escaping @MainActor (ModelLoadState) -> Void,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> any LoadedModel {
        guard let version = Self.models[model]?.version else { throw FluidAudioLoaderError.unknownModel }
        // FluidAudio puts a repo in the parent of the folder it is given, under the repo's own
        // folder name, which is this folder.
        let folder = folder(of: model, downloadBase: downloadBase)
        // A downloaded model loads from disk with no network request. FluidAudio's download
        // ends by compiling each model once to check it, so its first compile starts Preparing.
        if !isDownloaded(model, downloadBase: downloadBase) {
            let reports = DownloadProgressThrottle()
            // Called on a queue FluidAudio picks, as often as each chunk of bytes arrives.
            try await AsrModels.download(to: folder, version: version, progressHandler: { report in
                switch report.phase {
                case .downloading(_, let totalFiles):
                    guard let share = Self.downloadFraction(report.fractionCompleted, filesToDownload: totalFiles),
                          let fraction = reports.report(share) else { return }
                    Task { @MainActor in progress(fraction) }
                case .compiling:
                    if reports.markPreparing() { Task { @MainActor in phase(.loading) } }
                case .listing:
                    break
                }
            })
            if reports.markPreparing() { phase(.loading) }
        }
        // One encoder window, where FluidAudio's own load adds Phonon-2's two shorter ones
        // (planning 0037): with no compiled copy, each window costs a Neural Engine compile of
        // about a minute and then holds some 350 MB, to save a dictation 16 ms at most.
        // `loadLocal` blocks while Core ML compiles, so it runs off the main actor.
        let models: AsrModels
        do {
            models = try await Task.detached(priority: .userInitiated) {
                try AsrModels.loadLocal(from: folder, version: version)
            }.value
        } catch {
            // FluidAudio's own load downloads again the files that won't load.
            logger.error("Loading \(model, privacy: .public) from disk failed, so FluidAudio repairs it: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
            models = try await AsrModels.load(from: folder, version: version)
        }
        return FluidAudioModel(manager: AsrManager(config: .default, models: models), decoderLayers: version.decoderLayers)
    }

    // internal for testability — the download's fraction in one FluidAudio 0.18.3 report of the
    // repo download. Each model call reports its download as the first `fluidAudioDownloadShare`
    // of its own fraction, and only the first call fetches files: a later call, with nothing to
    // fetch, reports none, which says nothing about the download.
    nonisolated static func downloadFraction(_ fractionCompleted: Double, filesToDownload: Int) -> Double? {
        guard filesToDownload > 0 else { return nil }
        return min(max(fractionCompleted / Constants.fluidAudioDownloadShare, 0), 1)
    }
}

enum FluidAudioLoaderError: Error, LocalizedError {
    case unknownModel

    var errorDescription: String? { "River doesn’t know this FluidAudio model." }
}

/// A loaded Parakeet or Phonon model. They take no custom-dictionary terms: the prompt is
/// Whisper's (planning 0037). The encoder reads 15 s at a time, and FluidAudio splits a longer
/// clip into overlapping windows itself (planning 0039).
@MainActor
final class FluidAudioModel: LoadedModel {
    private let manager: AsrManager
    private let decoderLayers: Int

    init(manager: AsrManager, decoderLayers: Int) {
        self.manager = manager
        self.decoderLayers = decoderLayers
    }

    func transcribe(_ samples: [Float], dictionaryTerms: [String]) async throws -> String? {
        // Each call decodes one whole recording, so it starts from a fresh decoder state.
        var state = TdtDecoderState.make(decoderLayers: decoderLayers)
        let result: ASRResult
        do {
            result = try await manager.transcribe(ShortClip.padded(samples), decoderState: &state)
        } catch {
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }
        return Self.spokenText(result.text)
    }

    // internal for testability — these models write nothing for audio with no words, where
    // Whisper writes an annotation such as "[BLANK_AUDIO]": both are nothing said.
    nonisolated static func spokenText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
