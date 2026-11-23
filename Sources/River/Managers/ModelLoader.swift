import Foundation

/// A model in memory, ready to transcribe 16 kHz mono samples.
@MainActor
protocol LoadedModel: AnyObject {
    /// The text, or `TranscriptionError.emptyTranscription` / `.noSpeechDetected` when there is
    /// none. `dictionaryTerms` bias an engine that supports them (Whisper's prompt); others
    /// ignore them (planning 0037).
    func transcribe(_ samples: [Float], dictionaryTerms: [String]) async throws -> String
}

/// One engine's models on disk and in memory (planning 0037, ADR 0001). `ModelStore` is the
/// only caller: it picks a loader by the model's catalogue entry and hands it the download
/// folder, so nothing above it imports an engine or reaches a loader. Each conformer is the
/// only file that imports its engine; tests use a fake.
@MainActor
protocol ModelLoader {
    /// Whether the model's whole file set is on disk, so it loads without the network.
    func isDownloaded(_ model: String, downloadBase: URL) -> Bool
    /// The model's own folder, which Show in Finder reveals.
    func folder(of model: String, downloadBase: URL) -> URL
    /// Everything Delete removes, and what its confirmation counts (planning 0038).
    func files(of model: String, downloadBase: URL) -> [URL]
    /// Downloads the model if it is not on disk, then loads it. `phase` hears `.downloading`
    /// when a download starts that the caller could not foresee, and `.loading` once the files
    /// are on disk. `progress` hears how far the download has got, 0 to 1, rising (planning
    /// 0004); a load with nothing to download reports none.
    func load(
        _ model: String, downloadBase: URL, phase: @escaping @MainActor (ModelLoadState) -> Void,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> any LoadedModel
}

extension ModelLoader {
    func files(of model: String, downloadBase: URL) -> [URL] { [folder(of: model, downloadBase: downloadBase)] }
}
