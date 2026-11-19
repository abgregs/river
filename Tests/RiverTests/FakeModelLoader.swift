import Foundation
@testable import River

/// A loader that never touches the disk or the network (planning 0037, ADR 0001): every load
/// succeeds at once unless its model is in `failing`, so the switching logic in
/// `TranscriptionManager` is tested without a real model.
@MainActor
final class FakeModelLoader: ModelLoader {
    struct LoadFailed: Error {}

    /// Models whose load throws. Change it between loads to make a retry succeed.
    var failing: Set<String> = []
    /// Models that read as downloaded, so a load starts as Preparing rather than Downloading.
    var downloaded: Set<String> = []
    /// Every load asked for, in order.
    private(set) var loads: [String] = []

    func isDownloaded(_ model: String, downloadBase: URL) -> Bool { downloaded.contains(model) }

    func folder(of model: String, downloadBase: URL) -> URL {
        downloadBase.appendingPathComponent("fake/\(model)", isDirectory: true)
    }

    func load(
        _ model: String, downloadBase: URL, phase: @escaping @MainActor (ModelLoadState) -> Void
    ) async throws -> any LoadedModel {
        loads.append(model)
        if failing.contains(model) { throw LoadFailed() }
        return FakeModel(name: model)
    }
}

/// A loaded fake model: it transcribes any audio as its own name, so a test can tell which
/// model wrote the text.
@MainActor
final class FakeModel: LoadedModel {
    let name: String

    init(name: String) { self.name = name }

    func transcribe(_ samples: [Float], dictionaryTerms: [String]) async throws -> String { name }
}

extension TranscriptionManager {
    /// A manager whose every engine loads through `loader`.
    static func withFake(_ loader: FakeModelLoader, modelName: String = Constants.defaultModel) -> TranscriptionManager {
        TranscriptionManager(modelName: modelName, loaders: { _ in loader })
    }
}
