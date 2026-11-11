import Foundation

/// One row of the Model section's catalogue (planning 0036, Model): which engine runs the
/// model, the exact name that engine downloads it by, and what the row shows. Pure data,
/// unit-tested without SwiftUI. The catalogue itself lives in `Constants.curatedModels`.
struct ModelOption: Identifiable, Equatable {
    /// The engine's own name for the model. For WhisperKit, the
    /// `argmaxinc/whisperkit-coreml` repo folder, e.g. `openai_whisper-small.en`: passed
    /// verbatim to `WhisperKit(model:)`, used as the on-disk cache directory, and stored in
    /// `Settings.selectedModel`.
    let name: String
    let label: String
    /// Who made the model, and the family it belongs to: the table groups rows by provider and
    /// lists each provider's families in its header.
    let provider: String
    let family: String
    /// What the model is good at. The size and requirements have their own columns.
    let summary: String
    /// What the first selection downloads, in decimal megabytes.
    let downloadMegabytes: Int
    let engine: SpeechEngine
    /// The oldest macOS major version the model runs on. A newer one than River's own minimum
    /// makes the row say so and refuse selection on older Macs.
    let minimumMacOS: Int
    let licence: ModelLicence
    var id: String { name }
}

/// The library that downloads and runs a model. FluidAudio joins it in PR 7a (planning 0037).
enum SpeechEngine: Equatable {
    case whisperKit
}

/// A model's licence, named in the About window's credits.
enum ModelLicence: Equatable {
    case mit

    var name: String {
        switch self {
        case .mit: "MIT"
        }
    }
}
