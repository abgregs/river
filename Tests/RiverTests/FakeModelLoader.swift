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
    /// What each model hears in any audio, in place of its own name; "" means no speech.
    var texts: [String: String] = [:]

    /// Whether each transcription waits for `finishTranscriptions()`, so a test can hold one
    /// open and see what else runs meanwhile.
    var holdsTranscriptions = false
    /// The most transcriptions that ran at once: the engines take one decode at a time.
    private(set) var mostTranscriptionsAtOnce = 0
    private var transcriptionsRunning = 0
    private var heldTranscriptions: [CheckedContinuation<Void, Never>] = []

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
        return FakeModel(name: model, loader: self)
    }

    /// How many transcriptions are waiting for `finishTranscriptions()`.
    var heldTranscriptionCount: Int { heldTranscriptions.count }

    /// Lets every held transcription run on.
    func finishTranscriptions() {
        let held = heldTranscriptions
        heldTranscriptions.removeAll()
        for transcription in held { transcription.resume() }
    }

    fileprivate func transcriptionStarted() async {
        transcriptionsRunning += 1
        mostTranscriptionsAtOnce = max(mostTranscriptionsAtOnce, transcriptionsRunning)
        if holdsTranscriptions { await withCheckedContinuation { heldTranscriptions.append($0) } }
    }

    fileprivate func transcriptionEnded() { transcriptionsRunning -= 1 }

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
/// model wrote the text, or as the loader's `texts` say, nil for "" as an engine that heard
/// no speech.
@MainActor
final class FakeModel: LoadedModel {
    let name: String
    private weak var loader: FakeModelLoader?

    init(name: String, loader: FakeModelLoader? = nil) {
        self.name = name
        self.loader = loader
    }

    func transcribe(_ samples: [Float], dictionaryTerms: [String]) async throws -> String? {
        await loader?.transcriptionStarted()
        loader?.transcriptionEnded()
        let text = loader?.texts[name] ?? name
        return text.isEmpty ? nil : text
    }
}

extension TranscriptionManager {
    /// A manager whose every engine loads through `loader`, in River's real models folder
    /// unless the test passes its own.
    static func withFake(_ loader: FakeModelLoader, modelName: String = Constants.defaultModel,
                         downloadBase: URL = ModelStore.defaultDownloadBase()) -> TranscriptionManager {
        TranscriptionManager(modelName: modelName, store: ModelStore(downloadBase: downloadBase, loaders: { _ in loader }))
    }
}
