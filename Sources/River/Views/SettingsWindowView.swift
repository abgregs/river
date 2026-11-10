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

    init(appState: AppState, capabilities: [any Capability], updater: UpdaterManager, selectModel: @escaping (String) -> Void) {
        self.appState = appState
        self.capabilities = capabilities
        self.updater = updater
        self.selectModel = selectModel
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
            case .shortcuts: ShortcutsPane()
            case .dictation: DictationPane()
            case .model: ModelPane(appState: model.appState, selectModel: model.selectModel)
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
                RailItem(section: section, isCurrent: model.section == section,
                         showsBadge: section == .permissions && model.permissionMissing) {
                    model.section = section
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                KawaMarkShape()
                    .fill(ink.secondary)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(Self.versionLine)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(ink.secondary)
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, Constants.settingsTitleBarHeight + 8)
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
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
    let showsBadge: Bool
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
                if showsBadge {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .accessibilityLabel("A permission is missing")
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
    @AppStorage(Settings.activationKeyCode.name)
    private var activationKeyCode: Int = Settings.activationKeyCode.defaultValue
    @AppStorage(Settings.activationMode.name)
    private var activationMode: ActivationMode = Settings.activationMode.defaultValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Interim until PR 8's recorder (planning 0036, Interim rows).
            SettingsRow(label: "Dictation shortcut", divider: false) {
                RiverPopUp(title: "Dictation shortcut",
                           options: ActivationKeyOption.all.map { ($0.keyCode, $0.label) },
                           selection: $activationKeyCode)
            }
            if let warning = ActivationKeyOption.capsLockHoldWarning(keyCode: activationKeyCode, mode: activationMode) {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .padding(.bottom, 8)
            }
            // The cancel sentence never breaks across lines (planning 0036, Cancel line).
            SettingsRow(label: "Start by",
                        description: Text("\(activationMode.description) ")
                            + Text(ActivationKeyOption.cancelLine(keyCode: activationKeyCode)
                                .replacingOccurrences(of: " ", with: "\u{00A0}"))) {
                RiverSegmentedChoice(title: "Start by",
                                     options: ActivationMode.allCases.map { ($0, $0.label) },
                                     selection: $activationMode)
            }
        }
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

/// Interim: the model in use, its status, and a pop-up to choose another. The catalogue
/// replaces it in the next change.
private struct ModelPane: View {
    let appState: AppState
    let selectModel: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = SettingsInk(colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(label: "Model", divider: false) {
                RiverPopUp(title: "Model",
                           options: Constants.curatedModels.map { ($0.name, $0.label) },
                           selection: Binding(get: { appState.modelSwitch?.target ?? appState.activeModel },
                                              set: { selectModel($0) }))
            }
            SettingsRow(label: "Status") {
                Text(String(describing: appState.modelSwitch?.phase ?? .ready))
                    .foregroundStyle(ink.secondary)
            }
        }
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
