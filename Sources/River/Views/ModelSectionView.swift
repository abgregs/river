import AppKit
import SwiftUI

/// The Model section (planning 0036, Model; settings panel study, round 14): the model in use
/// with its status, and a switch in progress under it; a search and a provider filter; and the
/// catalogue's table, grouped by provider until the Download size column sorts it; and the
/// folder the models are saved in, with the space they take (planning 0038). A downloaded
/// row's ⋯ menu, shown on hover or keyboard focus and on a right-click, offers Show in Finder
/// and, for a model River is neither using nor loading, Delete…. The window grows to
/// 820 × 540 for this section, and the table scrolls inside it.
struct ModelSectionView: View {
    let appState: AppState
    let selectModel: (String) -> Void
    let deleteModel: (String) throws -> Void
    @State private var query = ""
    @State private var provider: String?
    @State private var sort = ModelCatalogue.Sort.grouped
    @State private var downloaded: Set<String> = []
    @State private var modelsSize: Int64?
    @State private var hoveredRow: String?
    @FocusState private var focusedRow: String?
    @State private var pendingDelete: PendingDelete?
    @State private var failedDelete: FailedDelete?
    @Environment(\.colorScheme) private var colorScheme

    init(appState: AppState, selectModel: @escaping (String) -> Void, deleteModel: @escaping (String) throws -> Void,
         hoveredRow: String? = nil) {
        self.appState = appState
        self.selectModel = selectModel
        self.deleteModel = deleteModel
        // internal for testability — the snapshot harness shows a row's ⋯ as the pointer would.
        _hoveredRow = State(initialValue: hoveredRow)
    }

    private struct PendingDelete { let model: ModelOption; let freed: Int64 }
    private struct FailedDelete { let model: ModelOption; let message: String }

    private let models = Constants.curatedModels
    private let downloadBase = TranscriptionManager.modelDownloadBase()
    // The status column fits "Downloaded" beside Select, its widest content. The ⋯ menu
    // follows it, 4 pt after, in its own column, so the status column keeps its layout; the
    // name column gives up the width it takes, so descriptions keep theirs, and the longest
    // name still wraps in two lines.
    private static let columnWidths = (name: 116.0, size: 76.0, status: 132.0, menu: 16.0)
    private static let menuGap = 4.0

    var body: some View {
        let ink = SettingsInk(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            CurrentModelBlock(appState: appState, selectModel: selectModel)
                .padding(.bottom, 12)
            HStack(spacing: 8) {
                ModelSearchField(text: $query)
                RiverPopUp(title: "Provider",
                           options: [(nil, "All providers")] + ModelCatalogue.providers(models).map { ($0, $0) },
                           selection: $provider)
            }
            .padding(.bottom, 8)
            table(ink)
            footer(ink)
        }
        .onAppear(perform: refreshDownloaded)
        .onChange(of: appState.modelSelection) { refreshDownloaded() }
        .alert(pendingDelete.map { "Delete \($0.model.label)?" } ?? "",
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { pending in
            Button("Delete model", role: .destructive) { delete(pending.model) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text("This frees \(ModelCatalogue.formattedSize(bytes: pending.freed)). You can download it again later.")
        }
    }

    // The note under the table, and where the models are saved: the folder, the space every
    // model in it takes as measured on disk, and Show in Finder.
    private func footer(_ ink: SettingsInk) -> some View {
        let folder = TranscriptionManager.modelsFolder(downloadBase: downloadBase)
        let path = (folder.path as NSString).abbreviatingWithTildeInPath
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sizes are downloads. Each model works entirely on this Mac once it is downloaded.")
                if let modelsSize {
                    Text("Models are saved in \(path) and take \(ModelCatalogue.formattedSize(bytes: modelsSize)).")
                } else {
                    Text("Models are saved in \(path).")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            if modelsSize != nil {
                Button("Show in Finder") { NSWorkspace.shared.open(folder) }
                    .buttonStyle(RiverBezelButtonStyle(height: 20, fontSize: 12))
            }
        }
        .padding(.top, 8)
        .alert(failedDelete.map { "Couldn’t delete \($0.model.label)" } ?? "",
               isPresented: Binding(get: { failedDelete != nil }, set: { if !$0 { failedDelete = nil } }),
               presenting: failedDelete) { _ in
            Button("OK") {}
        } message: { failed in
            Text(failed.message)
        }
    }

    private func table(_ ink: SettingsInk) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(spacing: 0) {
            header(ink)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    rows(ink)
                }
            }
        }
        .clipShape(shape)
        // The edge lies over the rows, so a pinned group header never covers it.
        .overlay(shape.strokeBorder(ink.opacity(0.12), lineWidth: 0.5))
        .frame(maxHeight: .infinity)
    }

    private func header(_ ink: SettingsInk) -> some View {
        HStack(spacing: 12) {
            Text("Model").frame(width: Self.columnWidths.name, alignment: .leading)
            Text("Description").frame(maxWidth: .infinity, alignment: .leading)
            Button { sort = sort.next } label: {
                HStack(spacing: 4) {
                    Text("Download size")
                    if sort != .grouped {
                        Image(systemName: sort == .ascending ? "chevron.up" : "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                }
            }
            .buttonStyle(.plain)
            .fixedSize()
            .frame(width: Self.columnWidths.size, alignment: .trailing)
            .accessibilityValue(sort == .grouped ? "Grouped by provider" : sort == .ascending ? "Smallest first" : "Largest first")
            Color.clear.frame(width: Self.columnWidths.status + Self.menuGap + Self.columnWidths.menu, height: 1)
                .accessibilityHidden(true)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(ink.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.08)).frame(height: 1) }
    }

    @ViewBuilder
    private func rows(_ ink: SettingsInk) -> some View {
        switch sort {
        case .grouped:
            let groups = ModelCatalogue.groups(models, query: query, provider: provider)
            if groups.isEmpty { noMatches(ink) }
            ForEach(groups, id: \.provider) { group in
                Section {
                    ForEach(Array(group.models.enumerated()), id: \.element.id) { index, model in
                        row(model, showsProvider: false, divider: index > 0, ink: ink)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(group.provider).fontWeight(.semibold)
                        Text(group.families).foregroundStyle(ink.secondary)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .background(Color(nsColor: Palette.windowTint))
                    .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.06)).frame(height: 1) }
                }
            }
        case .ascending, .descending:
            let list = ModelCatalogue.sorted(models, query: query, provider: provider, ascending: sort == .ascending)
            if list.isEmpty { noMatches(ink) }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, model in
                row(model, showsProvider: true, divider: index > 0, ink: ink)
            }
        }
    }

    private func row(_ model: ModelOption, showsProvider: Bool, divider: Bool, ink: SettingsInk) -> some View {
        let status = ModelCatalogue.status(
            of: model, selection: appState.modelSelection,
            macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            isDownloaded: downloaded.contains(model.name))
        let isDownloaded = downloaded.contains(model.name)
        let unavailable = if case .needsMacOS = status { true } else { false }
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(highlighted(model.label)).fontWeight(.medium)
                    .foregroundStyle(unavailable ? ink.opacity(0.7) : ink.color)
                if showsProvider {
                    Text(highlighted(model.provider)).font(.system(size: 11)).foregroundStyle(ink.secondary)
                }
            }
            .frame(width: Self.columnWidths.name, alignment: .leading)
            Text(highlighted(model.summary))
                .font(.system(size: 11))
                .foregroundStyle(ink.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ModelCatalogue.formattedSize(megabytes: model.downloadMegabytes))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(unavailable ? ink.opacity(0.7) : ink.opacity(0.86))
                .frame(width: Self.columnWidths.size, alignment: .trailing)
            HStack(spacing: Self.menuGap) {
                ModelRowAction(model: model, status: status, selectModel: selectModel, focusedRow: $focusedRow)
                    .frame(width: Self.columnWidths.status, alignment: .trailing)
                rowMenuButton(model, status: status, isDownloaded: isDownloaded, ink: ink)
                    .frame(width: Self.columnWidths.menu)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
        .background(status == .inUse ? ink.opacity(0.07) : .clear)
        .overlay(alignment: .top) { if divider { Rectangle().fill(ink.opacity(0.06)).frame(height: 1) } }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { hoveredRow = model.name } else if hoveredRow == model.name { hoveredRow = nil }
        }
        .contextMenu { if isDownloaded { rowMenu(model, status: status) } }
        .accessibilityElement(children: .contain)
    }

    // A downloaded row's ⋯: shown while the pointer is over the row or the keyboard is on it,
    // and always there for VoiceOver.
    @ViewBuilder
    private func rowMenuButton(_ model: ModelOption, status: ModelCatalogue.RowStatus, isDownloaded: Bool, ink: SettingsInk) -> some View {
        if isDownloaded {
            Menu { rowMenu(model, status: status) } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 13)).foregroundStyle(ink.secondary)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .focused($focusedRow, equals: model.name)
            .opacity(hoveredRow == model.name || focusedRow == model.name ? 1 : 0)
            .accessibilityLabel("Actions for \(model.label)")
        }
    }

    // The ⋯ menu and the right-click menu: Show in Finder for any downloaded model, and
    // Delete… where `ModelCatalogue.offersDelete` allows it, absent rather than dimmed.
    @ViewBuilder
    private func rowMenu(_ model: ModelOption, status: ModelCatalogue.RowStatus) -> some View {
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([model.engine.loader.folder(of: model.name, downloadBase: downloadBase)])
        }
        if ModelCatalogue.offersDelete(status) {
            Divider()
            Button("Delete…") {
                pendingDelete = PendingDelete(model: model, freed: TranscriptionManager.diskUsage(of: model.engine.loader.files(of: model.name, downloadBase: downloadBase)))
            }
        }
    }

    private func delete(_ model: ModelOption) {
        do {
            try deleteModel(model.name)
        } catch {
            failedDelete = FailedDelete(model: model, message: LogRedaction.redactUserPaths(error.localizedDescription))
        }
        refreshDownloaded()
    }

    private func noMatches(_ ink: SettingsInk) -> some View {
        let described = query.trimmingCharacters(in: .whitespaces).isEmpty ? (provider ?? "") : query.trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 8) {
            Text("No models match “\(described)”.")
            Button("Show All Models") { query = ""; provider = nil }
                .buttonStyle(RiverBezelButtonStyle())
        }
        .font(.system(size: 12))
        .foregroundStyle(ink.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 22)
    }

    // The search's match, on a faint ink plate.
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let range = attributed.range(of: query, options: .caseInsensitive) else { return attributed }
        attributed[range].backgroundColor = SettingsInk(colorScheme).opacity(0.16)
        return attributed
    }

    // Which models are downloaded, and the models folder's size: on showing, on every change
    // to the selection (a download or load moving on), and after a delete.
    private func refreshDownloaded() {
        downloaded = Set(models.filter { $0.engine.loader.isDownloaded($0.name, downloadBase: downloadBase) }.map(\.name))
        modelsSize = TranscriptionManager.diskUsage(of: TranscriptionManager.modelsFolder(downloadBase: downloadBase))
    }
}

/// The model in use, its status, and a switch in progress (planning 0036: a new model takes
/// over only once it is ready; until then River keeps using the current one).
private struct CurrentModelBlock: View {
    let appState: AppState
    let selectModel: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = SettingsInk(colorScheme)
        let selection = appState.modelSelection
        let current = model(selection.inUse)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current?.label ?? selection.inUse).fontWeight(.semibold)
                    if let current {
                        Text("\(current.provider) · \(ModelCatalogue.formattedSize(megabytes: current.downloadMegabytes))")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(ink.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let status = ModelCatalogue.status(ofModelNamed: selection.inUse, in: selection) {
                    ModelPhaseStatus(status: status, barWidth: 96) { selectModel(selection.inUse) }
                }
            }
            if let next = selection.next, let target = model(next.target),
               let status = ModelCatalogue.status(ofModelNamed: next.target, in: selection) {
                HStack(spacing: 16) {
                    switchLine(target: target.label, current: current?.label ?? selection.inUse, status: status)
                        .font(.system(size: 11))
                        .foregroundStyle(ink.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ModelPhaseStatus(status: status, barWidth: 96) { selectModel(next.target) }
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.08)).frame(height: 1) }
                .padding(.top, 10)
            }
        }
    }

    private func switchLine(target: String, current: String, status: ModelCatalogue.RowStatus) -> Text {
        let name = Text(target).fontWeight(.medium).foregroundColor(SettingsInk(colorScheme).color)
        return switch status {
        case .failed: name + Text(" didn’t finish loading. River is still using \(current).")
        case .waiting: name + Text(" is ready. River switches to it after this dictation.")
        default: Text("Switching to ") + name + Text(" when it’s ready. Until then, River keeps using \(current).")
        }
    }

    private func model(_ name: String) -> ModelOption? {
        Constants.curatedModels.first { $0.name == name }
    }
}

/// The status beside the current model and the next one: Ready, Waiting, a load in progress
/// (an indeterminate bar: River gets no download percentage), or a failure with Try Again.
private struct ModelPhaseStatus: View {
    let status: ModelCatalogue.RowStatus
    let barWidth: Double
    let retry: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = SettingsInk(colorScheme)
        HStack(spacing: 8) {
            switch status {
            case .inUse:
                Image(systemName: "checkmark").font(.system(size: 11, weight: .medium))
                Text("Ready")
            case .waiting:
                Text("Waiting")
            case .downloading, .preparing:
                IndeterminateBar(width: barWidth)
                Text(status == .downloading ? "Downloading…" : "Preparing…")
            case .failed:
                Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                Text("Couldn’t load")
                Button("Try Again", action: retry).buttonStyle(RiverBezelButtonStyle())
            case .needsMacOS, .selectable:
                EmptyView()
            }
        }
        .foregroundStyle(ink.secondary)
        .fixedSize()
    }
}

/// A row's trailing cell: In use, Waiting, a load in progress, a macOS requirement, or Select.
private struct ModelRowAction: View {
    let model: ModelOption
    let status: ModelCatalogue.RowStatus
    let selectModel: (String) -> Void
    // Select shares the row's focus value with its ⋯ menu, so a keyboard-focused row shows it.
    let focusedRow: FocusState<String?>.Binding
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = SettingsInk(colorScheme)
        HStack(spacing: 8) {
            switch status {
            case .inUse:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .medium))
                    Text("In use").fontWeight(.medium)
                }
                .foregroundStyle(ink.color)
            case .waiting:
                Text("Waiting")
            case .downloading, .preparing:
                IndeterminateBar(width: 36)
                Text(status == .downloading ? "Downloading…" : "Preparing…")
            case .failed:
                Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                selectButton("Try Again")
            case .needsMacOS(let major):
                Text("Needs macOS \(major)")
            case .selectable(let isDownloaded):
                if isDownloaded { Text("Downloaded") }
                selectButton("Select")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(ink.secondary)
        .lineLimit(1)
        .fixedSize()
    }

    private func selectButton(_ title: String) -> some View {
        Button(title) { selectModel(model.name) }
            .buttonStyle(RiverBezelButtonStyle(height: 20, fontSize: 12))
            .focused(focusedRow, equals: model.name)
            .accessibilityLabel("\(title) \(model.label)")
    }
}

/// An indeterminate progress bar in ink: a short segment sliding along a faint track. Still,
/// at a faint full width, with Reduce Motion.
private struct IndeterminateBar: View {
    let width: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ink = SettingsInk(colorScheme)
        Capsule()
            .fill(ink.opacity(0.12))
            .frame(width: width, height: 4)
            .overlay(alignment: .leading) {
                if reduceMotion {
                    Capsule().fill(ink.opacity(0.35))
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(ink.opacity(0.7))
                            .frame(width: width * 0.34)
                            .offset(x: width * (-0.34 + 1.34 * t))
                    }
                }
            }
            .clipShape(Capsule())
            .accessibilityElement()
            .accessibilityLabel("In progress")
    }
}

/// The model search: AppKit's search field, whose own circled x is its one clear button.
private struct ModelSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search models"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search models")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
