import FluidAudio
import Foundation

/// The Parakeet and Phonon models' loader: the only file that imports FluidAudio (planning
/// 0037). A model's name is its FluidAudio repo folder, kept in River's one models folder
/// (planning 0038) as `models/FluidInference/<name>`, so the Model section's folder total,
/// Show in Finder and Delete cover it like a Whisper model.
struct FluidAudioLoader: ModelLoader {
    // FluidAudio 0.18.3's repo folder for each version River lists. `AsrModelVersion.repo`
    // is internal to FluidAudio, so the names are River's to keep in step.
    private static let versions: [String: AsrModelVersion] = [
        "parakeet-tdt-0.6b-v2-coreml": .v2,
        "phonon-2-coreml": .phonon2,
    ]

    func folder(of model: String, downloadBase: URL) -> URL {
        downloadBase.appendingPathComponent("models/FluidInference/\(model)", isDirectory: true)
    }

    /// FluidAudio's own load-ready check: every compiled model complete and the vocabulary
    /// present. A cut-off download leaves `.partial` files inside the folder, which fail it.
    func isDownloaded(_ model: String, downloadBase: URL) -> Bool {
        guard let version = Self.versions[model] else { return false }
        return AsrModels.modelsExist(at: folder(of: model, downloadBase: downloadBase), version: version)
    }

    func load(
        _ model: String, downloadBase: URL, phase: @escaping @MainActor (ModelLoadState) -> Void
    ) async throws -> any LoadedModel {
        guard let version = Self.versions[model] else { throw FluidAudioLoaderError.unknownModel }
        // FluidAudio puts a repo in the parent of the folder it is given, under the repo's own
        // folder name, which is this folder.
        let folder = folder(of: model, downloadBase: downloadBase)
        // A downloaded model loads from disk with no network request. FluidAudio's download
        // also compiles each model once to check it, so the first preparation is part of
        // Downloading.
        if !isDownloaded(model, downloadBase: downloadBase) {
            try await AsrModels.download(to: folder, version: version)
            phase(.loading)
        }
        let models = try await AsrModels.load(from: folder, version: version)
        return FluidAudioModel(manager: AsrManager(config: .default, models: models), decoderLayers: version.decoderLayers)
    }
}

enum FluidAudioLoaderError: Error, LocalizedError {
    case unknownModel

    var errorDescription: String? { "River doesn’t know this FluidAudio model." }
}

/// A loaded Parakeet or Phonon model. They take no custom-dictionary terms: the prompt is
/// Whisper's (planning 0037).
@MainActor
final class FluidAudioModel: LoadedModel {
    private let manager: AsrManager
    private let decoderLayers: Int

    init(manager: AsrManager, decoderLayers: Int) {
        self.manager = manager
        self.decoderLayers = decoderLayers
    }

    func transcribe(_ samples: [Float], dictionaryTerms: [String]) async throws -> String {
        // Each call decodes one whole recording, so it starts from a fresh decoder state.
        var state = TdtDecoderState.make(decoderLayers: decoderLayers)
        let result: ASRResult
        do {
            result = try await manager.transcribe(samples, decoderState: &state)
        } catch {
            throw TranscriptionError.transcriptionFailed(underlying: error)
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // These models write nothing for audio with no words, where Whisper writes an
        // annotation such as "[BLANK_AUDIO]": both are the quiet no-speech case.
        guard !text.isEmpty else { throw TranscriptionError.noSpeechDetected }
        return text
    }
}
