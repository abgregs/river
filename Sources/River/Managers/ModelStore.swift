import Foundation

/// The models on this Mac (planning 0037, 0038): the one folder every engine downloads into,
/// and the one route from a model's name, through its catalogue entry, to its engine's
/// loader. `TranscriptionManager` loads and deletes through it, and the Model section reads
/// "Downloaded", Show in Finder, the space a delete frees and the folder's total from the same
/// value, so what the section shows is what a delete removes. A name the catalogue doesn't
/// list has no loader: it is never downloaded, has no folder or files, and fails to load.
/// Tests pass a temporary folder, a fake loader, or both. Everything that reaches a loader is
/// main-actor isolated, as the loaders are; making one is not, so it can be a default argument.
struct ModelStore {
    /// The download root, under Application Support (`defaultDownloadBase`) except in tests.
    let downloadBase: URL
    private let loaders: @MainActor (SpeechEngine) -> any ModelLoader

    init(downloadBase: URL = ModelStore.defaultDownloadBase(),
         loaders: @escaping @MainActor (SpeechEngine) -> any ModelLoader = { ModelStore.engineLoader($0) }) {
        self.downloadBase = downloadBase
        self.loaders = loaders
    }

    // internal for testability — the model download root. Application Support (not
    // WhisperKit's ~/Documents default) so model downloads never trip the Documents-folder
    // TCC prompt (planning 0010). Pure (no I/O); each loader creates the folders it
    // downloads into.
    static func defaultDownloadBase() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Constants.modelCacheFolderName, isDirectory: true)
    }

    // The loader that downloads and runs each engine's models: the only place a real loader
    // is made.
    @MainActor private static func engineLoader(_ engine: SpeechEngine) -> any ModelLoader {
        switch engine {
        case .whisperKit: WhisperKitLoader()
        case .fluidAudio: FluidAudioLoader()
        }
    }

    @MainActor private func loader(for model: String) -> (any ModelLoader)? {
        ModelCatalogue.option(named: model).map { loaders($0.engine) }
    }

    /// The folder every model's files live in, whatever its engine: what the Model section
    /// names and shows in Finder.
    var modelsFolder: URL { downloadBase.appendingPathComponent("models", isDirectory: true) }

    /// Whether the model's whole file set is on disk, so it loads without the network.
    @MainActor func isDownloaded(_ model: String) -> Bool {
        loader(for: model)?.isDownloaded(model, downloadBase: downloadBase) ?? false
    }

    /// The model's own folder, which Show in Finder reveals.
    @MainActor func folder(of model: String) -> URL? {
        loader(for: model)?.folder(of: model, downloadBase: downloadBase)
    }

    /// Everything a delete removes: the model's folder, and for a Whisper model its download
    /// records (planning 0038).
    @MainActor func files(of model: String) -> [URL] {
        loader(for: model)?.files(of: model, downloadBase: downloadBase) ?? []
    }

    /// What deleting the model frees, measured on disk as Finder counts it.
    @MainActor func spaceFreed(byDeleting model: String) -> Int64 {
        files(of: model).compactMap(Self.diskUsage(of:)).reduce(0, +)
    }

    /// The space every file in the models folder takes, tokenizers and download records
    /// included. `nil` when the folder isn't there yet.
    func totalSize() -> Int64? { Self.diskUsage(of: modelsFolder) }

    /// Downloads the model if it is not on disk, then loads it (`ModelLoader.load`).
    @MainActor func load(
        _ model: String, phase: @escaping @MainActor (ModelLoadState) -> Void,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> any LoadedModel {
        guard let loader = loader(for: model) else { throw ModelStoreError.notInCatalogue }
        return try await loader.load(model, downloadBase: downloadBase, phase: phase, progress: progress)
    }

    // internal for testability — the space `url` takes on disk, as Finder counts it: the
    // blocks allocated to every file under it, in bytes. `nil` when nothing is there.
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
}

enum ModelStoreError: Error, LocalizedError {
    case notInCatalogue

    var errorDescription: String? { "River doesn’t list this model." }
}
