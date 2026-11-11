import Foundation

/// What River credits in the About window and its notices file (planning 0036, The panel ends
/// with the version line): the models first, then the open-source software built into the app.
/// **Why:** River ships MIT and Apache-2.0 packages and MIT-licensed Whisper models, and both
/// licences require their notice to travel with every copy. The full texts are in
/// `noticesFileName`, which `make verify` requires in the bundle.
enum Credits {
    struct Software: Equatable {
        /// The package's identity in `Package.resolved`.
        let identity: String
        let name: String
        let holder: String
        let licence: String
    }

    static let noticesFileName = "ThirdPartyNotices.txt"

    /// Every package linked into River or embedded in its bundle.
    static let software: [Software] = [
        Software(identity: "whisperkit", name: "WhisperKit", holder: "argmax, inc.", licence: "MIT"),
        Software(identity: "swift-transformers", name: "swift-transformers", holder: "Hugging Face", licence: "Apache-2.0"),
        Software(identity: "swift-jinja", name: "swift-jinja", holder: "Hugging Face", licence: "Apache-2.0"),
        Software(identity: "swift-collections", name: "Swift Collections", holder: "Apple Inc.", licence: "Apache-2.0"),
        Software(identity: "swift-crypto", name: "Swift Crypto", holder: "Apple Inc.", licence: "Apache-2.0"),
        Software(identity: "yyjson", name: "yyjson", holder: "YaoYuan", licence: "MIT"),
        Software(identity: "sparkle", name: "Sparkle", holder: "the Sparkle Project", licence: "MIT"),
    ]

    /// Resolved packages that build tools use but River never links, so it ships no copy.
    static let notShipped: Set<String> = ["swift-argument-parser", "swift-asn1"]

    /// Who converted an engine's models to Core ML, credited with each model family.
    static func coreMLConverter(for engine: SpeechEngine) -> String {
        switch engine {
        case .whisperKit: "Argmax"
        }
    }

    /// The About window's Credits text: one paragraph per model family, then the software.
    static func aboutText(models: [ModelOption]) -> String {
        var families: [(key: String, models: [ModelOption])] = []
        for model in models {
            let key = "\(model.provider) \(model.family)"
            if let index = families.firstIndex(where: { $0.key == key }) {
                families[index].models.append(model)
            } else {
                families.append((key, [model]))
            }
        }
        let modelLines = families.map { family in
            let first = family.models[0]
            return "\(family.key): \(family.models.map(\.label).joined(separator: ", ")). \(first.licence.name) licence. "
                + "Converted to Core ML by \(coreMLConverter(for: first.engine))."
        }
        let softwareLines = software.map { "\($0.name), \($0.holder). \($0.licence) licence." }
        return (["Models"] + modelLines + ["", "Software"] + softwareLines
                + ["", "The full licence texts are in \(noticesFileName), in River’s Resources folder."])
            .joined(separator: "\n")
    }
}
