import Foundation

/// The Model section's table logic (planning 0036, Model; settings panel study, rounds 4 to 14),
/// pure so it is tested without SwiftUI: which rows a search and the provider filter keep, how
/// they group or sort, and what each row's trailing cell shows.
enum ModelCatalogue {
    /// The Download size column cycles: provider groups, smallest first, largest first, groups.
    enum Sort: Equatable {
        case grouped, ascending, descending

        var next: Sort {
            switch self {
            case .grouped: .ascending
            case .ascending: .descending
            case .descending: .grouped
            }
        }
    }

    struct Group: Equatable {
        let provider: String
        /// The provider's families among the rows shown, for the group header.
        let families: String
        let models: [ModelOption]
    }

    /// What a row's trailing cell shows.
    enum RowStatus: Equatable {
        case inUse
        case downloading
        case preparing
        /// The load failed; the row offers Try Again.
        case failed
        case needsMacOS(Int)
        case selectable(downloaded: Bool)
    }

    /// Providers in catalogue order, for the filter's pop-up.
    static func providers(_ models: [ModelOption]) -> [String] {
        distinct(models.map(\.provider))
    }

    /// A row stays when it is from `provider` (or any, for `nil`) and the query, trimmed, is
    /// empty or found, ignoring case, in its name, description, provider or family.
    static func matches(_ model: ModelOption, query: String, provider: String?) -> Bool {
        if let provider, model.provider != provider { return false }
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [model.label, model.summary, model.provider, model.family].contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// The rows kept, grouped by provider in catalogue order, smallest download first in each.
    static func groups(_ models: [ModelOption], query: String, provider: String?) -> [Group] {
        providers(models).compactMap { name in
            let rows = models.filter { $0.provider == name && matches($0, query: query, provider: provider) }
                .sorted { $0.downloadMegabytes < $1.downloadMegabytes }
            guard !rows.isEmpty else { return nil }
            return Group(provider: name, families: distinct(rows.map(\.family)).joined(separator: ", "), models: rows)
        }
    }

    /// The rows kept as one list by download size, for a sorted table.
    static func sorted(_ models: [ModelOption], query: String, provider: String?, ascending: Bool) -> [ModelOption] {
        models.filter { matches($0, query: query, provider: provider) }
            .sorted { ascending ? $0.downloadMegabytes < $1.downloadMegabytes : $0.downloadMegabytes > $1.downloadMegabytes }
    }

    /// A row's trailing cell. The model in use reads "In use" once it is ready; until then, and
    /// for a model loading beside it, the row shows the load's phase.
    static func status(of model: ModelOption, activeModel: String, activeLoadState: ModelLoadState,
                       modelSwitch: ModelSwitch?, macOSMajor: Int, isDownloaded: Bool) -> RowStatus {
        if model.name == activeModel {
            switch activeLoadState {
            case .ready: return .inUse
            case .downloading: return .downloading
            case .loading: return .preparing
            case .failed: return .failed
            }
        }
        if let modelSwitch, modelSwitch.target == model.name {
            switch modelSwitch.phase {
            case .downloading: return .downloading
            case .preparing, .ready: return .preparing
            case .failed: return .failed
            }
        }
        if model.minimumMacOS > macOSMajor { return .needsMacOS(model.minimumMacOS) }
        return .selectable(downloaded: isDownloaded)
    }

    private static func distinct(_ values: [String]) -> [String] {
        values.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// "487 MB", "1.6 GB": decimal units, as the download sizes are.
    static func formattedSize(megabytes: Int) -> String {
        megabytes >= 1000 ? String(format: "%.1f GB", Double(megabytes) / 1000) : "\(megabytes) MB"
    }
}
