import Foundation
@testable import River

/// A loader that never touches the disk or the network (planning 0037, ADR 0001): every load
/// succeeds at once unless its model is in `failing`, so the switching logic in
/// `TranscriptionManager` is tested without a real model. A model in `held` loads only when
/// the test says, so a test can look at River mid-load and send what a real loader reports.
@MainActor
final class FakeModelLoader: ModelLoader {
    struct LoadFailed: Error {}

    /// Models whose load throws. Change it between loads to make a retry succeed.
    var failing: Set<String> = []
    /// Models that read as downloaded, so a load starts as Preparing rather than Downloading.
    var downloaded: Set<String> = []
    /// Models whose load waits for `finishLoad(of:)`. A cancelled load still waits, as a real
    /// one does: cancellation is cooperative, and the Core ML load runs on.
    var held: Set<String> = []
    /// Every load asked for, in order.
    private(set) var loads: [String] = []

    private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    // The last load of each model's reports, kept once it has ended so a test can send one late.
    private var reporters: [String: (phase: @MainActor (ModelLoadState) -> Void, progress: @MainActor (Double) -> Void)] = [:]

    func isDownloaded(_ model: String, downloadBase: URL) -> Bool { downloaded.contains(model) }

    func folder(of model: String, downloadBase: URL) -> URL {
        downloadBase.appendingPathComponent("fake/\(model)", isDirectory: true)
    }

    func load(
        _ model: String, downloadBase: URL, phase: @escaping @MainActor (ModelLoadState) -> Void,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> any LoadedModel {
        loads.append(model)
        reporters[model] = (phase, progress)
        if held.contains(model) {
            await withCheckedContinuation { waiting[model] = $0 }
        }
        if failing.contains(model) { throw LoadFailed() }
        return FakeModel(name: model)
    }

    /// Waits until a held load of `model` has started. Gives up after about a second, so a load
    /// that never starts fails the test's next expectation rather than hanging it.
    func loadStarted(_ model: String) async {
        for _ in 0..<200 {
            if waiting[model] != nil { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Ends a held load of `model`: it succeeds unless the model is in `failing`.
    func finishLoad(of model: String) { waiting.removeValue(forKey: model)?.resume() }

    /// Sends what the last load of `model` heard from its engine, as a real loader does while it
    /// downloads or prepares, or late, after the load has ended.
    func report(_ state: ModelLoadState, of model: String) { reporters[model]?.phase(state) }
    func report(progress fraction: Double, of model: String) { reporters[model]?.progress(fraction) }
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
    /// A manager whose every engine loads through `loader`, in River's real models folder
    /// unless the test passes its own.
    static func withFake(_ loader: FakeModelLoader, modelName: String = Constants.defaultModel,
                         downloadBase: URL = ModelStore.defaultDownloadBase()) -> TranscriptionManager {
        TranscriptionManager(modelName: modelName, store: ModelStore(downloadBase: downloadBase, loaders: { _ in loader }))
    }
}
