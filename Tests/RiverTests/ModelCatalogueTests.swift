import Testing
@testable import River

@Suite("Model catalogue")
struct ModelCatalogueTests {
    static let base = model("openai_whisper-base.en", "Whisper Base", "OpenAI", "Whisper", 147)
    static let small = model("openai_whisper-small.en", "Whisper Small", "OpenAI", "Whisper", 487)
    static let distil = model("distil", "Distil Large v3", "Hugging Face", "Distil-Whisper", 1515)
    static let sequoiaOnly = model("phonon", "Phonon-2", "Fermion Research", "Phonon", 378, minimumMacOS: 15)
    static let all = [small, distil, base, sequoiaOnly]

    // The search reaches every word a row shows, so a user who remembers "names" from a
    // description, or a provider, finds the row; the filter narrows to one provider.
    @Test("search matches name, description, provider or family, ignoring case and spaces")
    func searchMatchesEveryShownField() {
        #expect(ModelCatalogue.matches(Self.small, query: "  small ", provider: nil))
        #expect(ModelCatalogue.matches(Self.small, query: "STEADY", provider: nil))
        #expect(ModelCatalogue.matches(Self.distil, query: "hugging", provider: nil))
        #expect(ModelCatalogue.matches(Self.distil, query: "distil-whisper", provider: nil))
        #expect(!ModelCatalogue.matches(Self.small, query: "parakeet", provider: nil))
        #expect(!ModelCatalogue.matches(Self.small, query: "", provider: "Hugging Face"))
    }

    @Test("groups follow catalogue order, smallest first, and drop empty providers")
    func groupsByProvider() {
        let groups = ModelCatalogue.groups(Self.all, query: "", provider: nil)
        #expect(groups.map(\.provider) == ["OpenAI", "Hugging Face", "Fermion Research"])
        #expect(groups[0].models == [Self.base, Self.small])
        #expect(groups[0].families == "Whisper")
        #expect(ModelCatalogue.groups(Self.all, query: "distil", provider: nil).map(\.provider) == ["Hugging Face"])
    }

    // Round 5: one click sorts small to large, a second large to small, a third returns to
    // the groups, so the table is never stuck in a sorted view.
    @Test("the size column cycles grouped, ascending, descending, grouped")
    func sortCycles() {
        #expect(ModelCatalogue.Sort.grouped.next == .ascending)
        #expect(ModelCatalogue.Sort.ascending.next == .descending)
        #expect(ModelCatalogue.Sort.descending.next == .grouped)
        #expect(ModelCatalogue.sorted(Self.all, query: "", provider: nil, ascending: false).first == Self.distil)
        #expect(ModelCatalogue.sorted(Self.all, query: "", provider: nil, ascending: true).first == Self.base)
    }

    // A row must never offer Select for a model the Mac can't run, and the model in use only
    // reads "In use" once it actually is (planning 0036, 0037 AC 2).
    @Test("each row shows in use, a load phase, a macOS requirement, or Select")
    func rowStatus() {
        func status(_ model: ModelOption, load: ModelLoadState = .ready, switching: ModelSwitch? = nil, macOS: Int = 15) -> ModelCatalogue.RowStatus {
            ModelCatalogue.status(of: model, activeModel: Self.small.name, activeLoadState: load, modelSwitch: switching,
                                  waitingModel: nil, macOSMajor: macOS, isDownloaded: false)
        }
        #expect(status(Self.small) == .inUse)
        #expect(status(Self.small, load: .downloading) == .downloading)
        #expect(status(Self.small, load: .failed) == .failed)
        #expect(status(Self.base, switching: ModelSwitch(target: Self.base.name, phase: .preparing)) == .preparing)
        #expect(status(Self.base, switching: ModelSwitch(target: Self.base.name, phase: .failed)) == .failed)
        #expect(status(Self.sequoiaOnly, macOS: 14) == .needsMacOS(15))
        #expect(status(Self.sequoiaOnly, macOS: 15) == .selectable(downloaded: false))
    }

    // A Select pressed during a dictation does nothing until it ends, so the row must say so
    // rather than keep offering Select; a choice that is already loading keeps its progress.
    @Test("a model chosen during a dictation reads Waiting until it starts to load")
    func waitingStatus() {
        func status(_ model: ModelOption, waiting: String?, switching: ModelSwitch? = nil) -> ModelCatalogue.RowStatus {
            ModelCatalogue.status(of: model, activeModel: Self.small.name, activeLoadState: .ready, modelSwitch: switching,
                                  waitingModel: waiting, macOSMajor: 15, isDownloaded: true)
        }
        #expect(status(Self.base, waiting: Self.base.name) == .waiting)
        #expect(status(Self.distil, waiting: Self.base.name) == .selectable(downloaded: true))
        #expect(status(Self.small, waiting: Self.small.name) == .inUse)
        #expect(status(Self.base, waiting: Self.base.name, switching: ModelSwitch(target: Self.base.name, phase: .downloading)) == .downloading)
        #expect(status(Self.base, waiting: Self.base.name, switching: ModelSwitch(target: Self.base.name, phase: .failed)) == .waiting)
        #expect(status(Self.base, waiting: Self.base.name, switching: ModelSwitch(target: Self.distil.name, phase: .preparing)) == .waiting)
    }

    @Test("sizes read in decimal megabytes and gigabytes")
    func sizes() {
        #expect(ModelCatalogue.formattedSize(megabytes: 487) == "487 MB")
        #expect(ModelCatalogue.formattedSize(megabytes: 1639) == "1.6 GB")
    }

    private static func model(_ name: String, _ label: String, _ provider: String, _ family: String, _ size: Int,
                              minimumMacOS: Int = 14) -> ModelOption {
        ModelOption(name: name, label: label, provider: provider, family: family,
                    summary: name == "openai_whisper-small.en" ? "A steady all-rounder for everyday writing." : "\(label) summary.",
                    downloadMegabytes: size, engine: .whisperKit, minimumMacOS: minimumMacOS, licence: .mit)
    }
}
