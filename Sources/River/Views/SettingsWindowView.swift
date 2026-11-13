import Observation
import os
import ServiceManagement
import SwiftUI

/// What the Settings window shows and what it reaches: the section on screen, whether a
/// permission is missing (the rail's badge), and the app's parts behind its rows.
@MainActor
@Observable
final class SettingsWindowModel {
    var section: SettingsSection = .shortcuts
    var permissionMissing = false
    @ObservationIgnored let appState: AppState
    @ObservationIgnored let capabilities: [any Capability]
    @ObservationIgnored let updater: UpdaterManager
    @ObservationIgnored let selectModel: (String) -> Void
    @ObservationIgnored let recorder: ShortcutRecorderModel

    init(appState: AppState, capabilities: [any Capability], updater: UpdaterManager,
         shortcutHooks: ShortcutRecorderHooks, selectModel: @escaping (String) -> Void) {
        self.appState = appState
        self.capabilities = capabilities
        self.updater = updater
        self.selectModel = selectModel
        recorder = ShortcutRecorderModel(hooks: shortcutHooks)
    }
}

/// The Settings window's content (planning 0036): the rail of sections on the left, ending on
/// the version line, and the chosen section on the right. The window around it is native;
/// this view draws River's tint and its own monochrome controls.
struct SettingsWindowView: View {
    @Bindable var model: SettingsWindowModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = SettingsInk(colorScheme)
        HStack(spacing: 0) {
            SettingsRail(model: model)
                .frame(width: Constants.settingsRailWidth)
                .overlay(alignment: .trailing) { Rectangle().fill(ink.opacity(0.08)).frame(width: 1) }
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .font(.system(size: 13))
        .foregroundStyle(ink.color)
        .background(Color(nsColor: Palette.windowTint))
        .ignoresSafeArea()
        // ⌘W closes the window. River is a menu bar app with no menu bar of its own, so no
        // File menu supplies it.
        .background {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var pane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.section.label)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 10)
            switch model.section {
            case .shortcuts: ShortcutsPane(appState: model.appState, recorder: model.recorder)
            case .dictation: DictationPane()
            case .model: ModelSectionView(appState: model.appState, selectModel: model.selectModel)
            case .general: GeneralPane(updater: model.updater)
            case .permissions: PermissionsPane(capabilities: model.capabilities)
            }
        }
        .padding(.top, Constants.settingsTitleBarHeight + 12)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

private struct SettingsRail: View {
    @Bindable var model: SettingsWindowModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = SettingsInk(colorScheme)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(SettingsSection.allCases.enumerated()), id: \.element) { index, section in
                RailItem(section: section, isCurrent: model.section == section, badge: badge(for: section)) {
                    model.section = section
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Spacer(minLength: 0)
            // The version line opens the standard About window, whose Credits name the models
            // and software River ships (planning 0036). The menu bar menu gains no item.
            Button(action: Self.showAbout) {
                HStack(spacing: 7) {
                    KawaMarkShape()
                        .fill(ink.secondary)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                    Text(Self.versionLine)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(ink.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the About window, with credits")
            .padding(.horizontal, 8)
        }
        .padding(.top, Constants.settingsTitleBarHeight + 8)
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }

    // Permissions while one is missing; Shortcuts while the dictation shortcut fails to
    // register, so it does nothing (planning 0036, Conflicts).
    private func badge(for section: SettingsSection) -> String? {
        switch section {
        case .permissions where model.permissionMissing: "A permission is missing"
        case .shortcuts where model.appState.isDictationShortcutFailing: "A shortcut is not working"
        default: nil
        }
    }

    static func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 2
        let credits = NSAttributedString(
            string: Credits.aboutText(models: Constants.curatedModels),
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor,
                         .paragraphStyle: paragraph])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    static var versionLine: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "River \(short) (\(build))"
    }
}

private struct RailItem: View {
    let section: SettingsSection
    let isCurrent: Bool
    /// The badge's spoken meaning; nil for no badge.
    let badge: String?
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        let ink = SettingsInk(colorScheme)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(isCurrent ? ink.color : ink.opacity(0.7))
                    .frame(width: 20)
                Text(section.label)
                    .fontWeight(isCurrent ? .medium : .regular)
                    .foregroundStyle(isCurrent ? ink.color : ink.opacity(0.86))
                Spacer(minLength: 0)
                if let badge {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .accessibilityLabel(badge)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(ink.opacity(isCurrent ? 0.1 : isHovered ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

// MARK: - Sections

private struct ShortcutsPane: View {
    let appState: AppState
    let recorder: ShortcutRecorderModel
    @AppStorage(Settings.dictationShortcut.name)
    private var dictationShortcut: Shortcut = Settings.dictationShortcut.defaultValue
    @AppStorage(Settings.activationMode.name)
    private var activationMode: ActivationMode = Settings.activationMode.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DictationShortcutRow(recorder: recorder, saved: dictationShortcut, appState: appState)
            SettingsRow(label: "Start by", description: Text(activationMode.description)) {
                RiverSegmentedChoice(title: "Start by",
                                     options: ActivationMode.allCases.map { ($0, $0.label) },
                                     selection: $activationMode)
            }
            // River's other shortcuts, from the list the recorder refuses (planning 0036, Cancel
            // recording). They are fixed, so a row has no Record button, and an empty button
            // column keeps the keys in line with the other rows'. Esc joins fn with PR 9.
            ForEach(RiverShortcut.allCases, id: \.self) { river in
                SettingsRow(label: river.label) {
                    HStack(spacing: 8) {
                        ShortcutChip(keys: ShortcutText.keys(river.shortcut))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(ShortcutText.spoken(river.shortcut))
                        Color.clear.frame(width: DictationShortcutRow.buttonWidth, height: 1)
                    }
                }
            }
        }
        .onAppear { recorder.refresh(saved: dictationShortcut) }
        .onDisappear { recorder.stop() }
    }
}

/// The dictation shortcut and its Record button (planning 0036, The recorder). The line under
/// the row says how to record and why a shortcut was refused while recording; otherwise that
/// the shortcut is unavailable during a dictation, does nothing, or is one macOS also uses.
private struct DictationShortcutRow: View {
    static let buttonWidth: Double = 70

    let recorder: ShortcutRecorderModel
    let saved: Shortcut
    let appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakes = 0.0

    var body: some View {
        let isBusy = appState.state != .idle
        SettingsRow(label: "Dictation shortcut", description: line(isBusy: isBusy).map(text), divider: false) {
            HStack(spacing: 8) {
                chip
                    .modifier(RefusalShake(animatableData: shakes))
                    .onChange(of: recorder.refusals) { _, count in
                        withAnimation(reduceMotion ? nil : .timingCurve(0.3, 0, 0.3, 1, duration: 0.32)) { shakes = Double(count) }
                    }
                Button(action: recorder.toggle) {
                    Text(recorder.isRecording ? "Cancel" : "Record")
                        .frame(minWidth: Self.buttonWidth - 20)
                }
                .buttonStyle(RiverBezelButtonStyle())
                .disabled(isBusy)
                .help(isBusy ? RecorderLine.busy.text : "")
                .accessibilityLabel(recorder.isRecording ? "Cancel recording the dictation shortcut" : "Record the dictation shortcut")
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { recorder.buttonFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, frame in recorder.buttonFrame = frame }
                    }
                }
            }
        }
    }

    // One chip in every phase: a save animates from the recording outline it already shows.
    // A chip per phase would be a new view at each change, starting at its end state.
    private var chip: some View {
        let shown: (keys: ShortcutText.Keys, look: ShortcutChip.Look, label: String) = switch recorder.phase {
        case .recording: (recorder.tried ?? ShortcutText.keys(recorder.held), .recording, "Recording")
        case .saving(let shortcut): (ShortcutText.keys(shortcut), .saving, ShortcutText.spoken(shortcut))
        case .idle: (ShortcutText.keys(saved), .saved, ShortcutText.spoken(saved))
        }
        return ShortcutChip(keys: shown.keys, look: shown.look, isTried: recorder.tried != nil, startedAt: recorder.startedAt)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shown.label)
    }

    private func line(isBusy: Bool) -> RecorderLine? {
        if recorder.isRecording { return recorder.line }
        if isBusy { return .busy }
        if let registration = appState.dictationRegistration, let failure = RecorderLine.notWorking(registration) {
            return failure
        }
        return recorder.isSystemShortcut ? .macOSAlsoUses : nil
    }

    // A refusal, a warning and a failure are full ink, each with its own symbol, so they differ
    // without color; a hint stays at the description's strength.
    private func text(_ line: RecorderLine) -> Text {
        let symbol: String? = switch line.kind {
        case .hint: nil
        case .refusal: "exclamationmark.circle"
        case .warning: "info.circle"
        case .failure: "exclamationmark.triangle"
        }
        guard let symbol else { return Text(line.text) }
        return (Text(Image(systemName: symbol)) + Text(" ") + Text(line.text)).foregroundColor(SettingsInk(colorScheme).color)
    }
}

private struct DictationPane: View {
    @AppStorage(Settings.playFeedbackSounds.name)
    private var playFeedbackSounds: Bool = Settings.playFeedbackSounds.defaultValue
    @AppStorage(Settings.keepMicrophoneReady.name)
    private var keepMicrophoneReady: Bool = Settings.keepMicrophoneReady.defaultValue
    @AppStorage(Settings.streamingDictation.name)
    private var streamingDictation: Bool = Settings.streamingDictation.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(label: "Play sounds when dictation starts and stops", divider: false) {
                Toggle("Play sounds when dictation starts and stops", isOn: $playFeedbackSounds).labelsHidden()
            }
            SettingsRow(label: "Keep the microphone ready",
                        description: Text("Your first word isn’t cut off. The microphone indicator stays on while River is open and able to dictate. When off, River opens the microphone only while you dictate.")) {
                Toggle("Keep the microphone ready", isOn: $keepMicrophoneReady).labelsHidden()
            }
            // Interim until PR 10 removes it (planning 0034, decision 1).
            SettingsRow(label: "Transcribe while I speak",
                        description: Text("Shows the text above the indicator as you talk. It is typed when you stop, as before.")) {
                Toggle("Transcribe while I speak", isOn: $streamingDictation).labelsHidden()
            }
        }
        .toggleStyle(RiverSwitchStyle())
    }
}

private struct GeneralPane: View {
    let updater: UpdaterManager
    @AppStorage(Settings.launchAtLogin.name)
    private var launchAtLogin: Bool = Settings.launchAtLogin.defaultValue
    @State private var checksAutomatically: Bool?
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(label: "Open River at login", divider: false) {
                Toggle("Open River at login", isOn: $launchAtLogin).labelsHidden()
                    .onChange(of: launchAtLogin) { _, enabled in updateLaunchAtLogin(enabled) }
            }
            // Release builds only: a dev build never starts the updater, so it has no value.
            if let checks = checksAutomatically {
                SettingsRow(label: "Check for updates automatically") {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { checks },
                        set: { updater.setAutomaticallyChecksForUpdates($0); checksAutomatically = $0 }
                    )).labelsHidden()
                }
            }
        }
        .toggleStyle(RiverSwitchStyle())
        .onAppear { checksAutomatically = updater.automaticallyChecksForUpdates }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            logger.info("Launch at login \(enabled ? "registered" : "unregistered", privacy: .public)")
        } catch {
            logger.error("Launch at login update failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
        }
    }
}

private struct PermissionsPane: View {
    let capabilities: [any Capability]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(capabilities.enumerated()), id: \.offset) { index, capability in
                PermissionRow(capability: capability, divider: index > 0)
            }
        }
    }
}

private struct PermissionRow: View {
    let capability: any Capability
    let divider: Bool
    @State private var status: CapabilityStatus
    @Environment(\.colorScheme) private var colorScheme

    init(capability: any Capability, divider: Bool) {
        self.capability = capability
        self.divider = divider
        _status = State(initialValue: capability.currentStatus)
    }

    var body: some View {
        let ink = SettingsInk(colorScheme)
        SettingsRow(label: capability.displayName, description: Text(capability.usageSummary), divider: divider) {
            if status == .granted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .medium))
                    Text("Granted")
                }
                .foregroundStyle(ink.secondary)
                .accessibilityElement(children: .combine)
            } else {
                Button("Open System Settings…") { capability.openSystemSettings() }
                    .buttonStyle(RiverBezelButtonStyle())
            }
        }
        .onReceive(capability.status) { status = $0 }
    }
}
