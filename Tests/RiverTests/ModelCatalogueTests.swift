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
        func status(_ model: ModelOption, load: ModelLoadState = .ready, next: ModelSwitch? = nil, macOS: Int = 15) -> ModelCatalogue.RowStatus {
            ModelCatalogue.status(of: model, selection: ModelSelection(inUse: Self.small.name, inUseState: load, next: next),
                                  macOSMajor: macOS, isDownloaded: false)
        }
        #expect(status(Self.small) == .inUse)
        #expect(status(Self.small, load: .downloading) == .downloading)
        #expect(status(Self.small, load: .failed) == .failed)
        #expect(status(Self.base, next: ModelSwitch(target: Self.base.name, phase: .preparing)) == .preparing)
        #expect(status(Self.base, next: ModelSwitch(target: Self.base.name, phase: .failed)) == .failed)
        #expect(status(Self.distil, next: ModelSwitch(target: Self.base.name, phase: .preparing)) == .selectable(downloaded: false))
        #expect(status(Self.sequoiaOnly, macOS: 14) == .needsMacOS(15))
        #expect(status(Self.sequoiaOnly, macOS: 15) == .selectable(downloaded: false))
    }

    // A model ready beside the one in use is only waiting for the dictation in progress to
    // end, so it must not read "Preparing" with a moving bar; and the row and the line above
    // the table read the same mapping, so they cannot disagree.
    @Test("a model ready beside the one in use reads Waiting, in its row and its status line")
    func readyNextModelIsWaiting() {
        let selection = ModelSelection(inUse: Self.small.name, inUseState: .ready,
                                       next: ModelSwitch(target: Self.base.name, phase: .ready))
        #expect(ModelCatalogue.status(of: Self.base, selection: selection, macOSMajor: 15, isDownloaded: true) == .waiting)
        #expect(ModelCatalogue.status(ofModelNamed: Self.base.name, in: selection) == .waiting)
        #expect(ModelCatalogue.status(ofModelNamed: Self.small.name, in: selection) == .inUse)
        #expect(ModelCatalogue.status(ofModelNamed: Self.distil.name, in: selection) == nil)
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
