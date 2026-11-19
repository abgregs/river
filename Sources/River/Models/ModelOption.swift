import Foundation

/// One row of the Model section's catalogue (planning 0036, Model): which engine runs the
/// model, the exact name that engine downloads it by, and what the row shows. Pure data,
/// unit-tested without SwiftUI. The catalogue itself lives in `Constants.curatedModels`.
struct ModelOption: Identifiable, Equatable {
    /// The engine's own name for the model, stored in `Settings.selectedModel`. For WhisperKit,
    /// the `argmaxinc/whisperkit-coreml` repo folder, e.g. `openai_whisper-small.en`, passed
    /// verbatim to `WhisperKit(model:)` and naming its folder on disk; for FluidAudio, its repo
    /// name, e.g. `parakeet-tdt-0.6b-v2-coreml`, whose folder `FluidAudioLoader` finds.
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
    /// The model this one was derived from, which its licence asks the credit to name too
    /// (Phonon-2 is a retraining of NVIDIA's Parakeet TDT 0.6B v3).
    var basedOn: String? = nil
    var id: String { name }
}

/// The library that downloads and runs a model (planning 0037). `loader` maps each to its
/// `ModelLoader`.
enum SpeechEngine: Equatable {
    case whisperKit
    case fluidAudio
}

/// A model's licence, named in the About window's credits.
enum ModelLicence: Equatable {
    case mit
    case ccBy4

    var name: String {
        switch self {
        case .mit: "MIT"
        case .ccBy4: "CC BY 4.0"
        }
    }

    /// Where the licence lives, for one that asks for a link with the credit.
    var link: String? {
        switch self {
        case .mit: nil
        case .ccBy4: "https://creativecommons.org/licenses/by/4.0/"
        }
    }
}
