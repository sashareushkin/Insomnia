import AppKit
import SwiftUI

/// Root navigation and window-scoped editing state for Settings.
/// Configuration remains write-through to `manager.config` and config.json.
struct SettingsView: View {
    /// Apple Platform Security, “Hardware microphone disconnect”.
    static let microphoneNote = "On Mac laptops with Apple silicon or a T2 chip, closing the lid disconnects the built-in microphone in hardware. Recording a meeting with the lid closed needs AirPods or an external mic."

    let manager: SessionManager
    let secrets: any HotspotSecretStore
    let locationPermission: LocationPermission
    let loginItem: LoginItem
    let releases: ReleaseChecker

    @State private var selection: SettingsSection = .general
    @State private var newPreset = ""
    @State private var presetError: String?
    @State private var newFreezeBundle = ""
    @State private var newAgentBundle = ""
    @State private var newTmuxTarget = ""
    /// Kept above destination views so switching sections cannot discard an
    /// edit or an in-flight keychain read/save.
    @State private var hotspot = HotspotPasswordField()
    @State private var localization = LocalizationManager.shared
    @State private var wouldFreeze: [String] = []

    var body: some View {
        let language = localization.language
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsSection.allCases) { section in
                    Label {
                        Text(L10n.string(section.titleKey, language: language))
                    } icon: {
                        Image(systemName: section.symbol)
                            .font(.system(size: SettingsLayout.sidebarSymbolSize))
                            .frame(width: 20)
                    }
                    .tag(section)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.regularMaterial, ignoresSafeAreaEdges: .top)
            .navigationSplitViewColumnWidth(
                min: SettingsLayout.sidebarColumnWidth,
                ideal: SettingsLayout.sidebarColumnWidth,
                max: SettingsLayout.sidebarColumnWidth
            )
        } detail: {
            destination(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(L10n.string(selection.titleKey, language: language))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: SettingsLayout.windowContentSize.width,
            minHeight: SettingsLayout.windowContentSize.height
        )
        .environment(\.locale, language.locale)
        .onAppear {
            loadPassword()
            refreshWouldFreeze()
            // macOS may have approved or removed the item since launch.
            loginItem.refresh()
        }
        // The failover can report a password unreadable while Settings is
        // open, and an SSID edit makes a notice about another hotspot stale.
        .onChange(of: manager.services?.status.hotspotPasswordReport) { recheckPassword() }
        .onChange(of: HotspotSSID.normalized(manager.config.hotspotSSID)) { recheckPassword() }
        // The automatic-freeze preview follows config edits and app launches
        // or terminations, regardless of which section is currently selected.
        .onChange(of: manager.config) { refreshWouldFreeze() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshWouldFreeze() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshWouldFreeze() }
    }

    @ViewBuilder
    private func destination(for section: SettingsSection) -> some View {
        switch section.destination {
        case .general:
            GeneralSettingsView(manager: manager, localization: localization, loginItem: loginItem, releases: releases)
        case .timer:
            TimerSettingsView(manager: manager, newPreset: $newPreset, presetError: $presetError)
        case .lidClose:
            LidCloseSettingsView(manager: manager)
        case .applications:
            ApplicationsSettingsView(
                manager: manager,
                newFreezeBundle: $newFreezeBundle,
                newAgentBundle: $newAgentBundle,
                wouldFreeze: wouldFreezeText
            )
        case .power:
            PowerSettingsView(manager: manager)
        case .network:
            NetworkSettingsView(
                manager: manager,
                locationPermission: locationPermission,
                hotspot: $hotspot,
                savePassword: savePassword
            )
        case .tmux:
            TmuxSettingsView(manager: manager, newTarget: $newTmuxTarget)
        }
    }

    private var wouldFreezeText: String {
        guard manager.config.freezeAllApps else { return L10n.string("Would freeze now: the list above only") }
        return wouldFreeze.isEmpty
            ? L10n.string("Would freeze now: nothing else")
            : L10n.format("Would freeze now: %@", wouldFreeze.joined(separator: ", "))
    }

    /// Same planner as the lid-close action, over the apps running now.
    private func refreshWouldFreeze() {
        let selfId = Bundle.main.bundleIdentifier ?? Paths.bundleIdentifier
        wouldFreeze = FreezePlanner.automaticCandidates(
            config: manager.config,
            apps: Freezer.runningApps(),
            selfBundleId: selfId
        ).map(\.name)
    }

    /// Fills the field when the settings window first appears. The parent
    /// owns this task state so destination changes cannot invalidate it.
    private func loadPassword() {
        let request = hotspot.startLoad(ssid: manager.config.hotspotSSID)
        Task {
            await Self.loadForField(request, secrets: secrets) {
                hotspot.finishRead($0, ssid: manager.config.hotspotSSID, password: $1.password, notice: $1.notice)
            }
        }
    }

    private func recheckPassword() {
        recheckPassword(hotspot.startRead(ssid: manager.config.hotspotSSID))
    }

    private func recheckPassword(_ request: HotspotPasswordField.Read) {
        Task {
            await Self.readForField(
                request,
                first: { await recheckedNotice() },
                again: { await recheckedNotice() },
                finish: { hotspot.finishRead($0, ssid: manager.config.hotspotSSID, password: $1.password, notice: $1.notice) }
            )
        }
    }

    private func recheckedNotice() async -> (password: String, notice: String?) {
        let notice = await Self.hotspotNotice(
            reported: manager.services?.status.hotspotPasswordReport,
            ssid: manager.config.hotspotSSID,
            reread: secrets.peek
        )
        return ("", notice)
    }

    /// Loads without a keychain prompt. An unreadable item leaves the field
    /// empty and explains why the user must enter it again.
    static func loadForField(
        _ request: HotspotPasswordField.Read,
        secrets: any HotspotSecretStore,
        finish: @MainActor (HotspotPasswordField.Read, (password: String, notice: String?)) -> HotspotPasswordField.ReadAnswer
    ) async {
        await readForField(
            request,
            first: { await loadedPassword(secrets.load) },
            again: { await loadedPassword(secrets.peek) },
            finish: finish
        )
    }

    /// Repeats a prompt-free read if the configured SSID changed while the
    /// first read waited. The newest answer updates the shared field state.
    static func readForField(
        _ request: HotspotPasswordField.Read,
        first: @MainActor () async -> (password: String, notice: String?),
        again: @MainActor () async -> (password: String, notice: String?),
        finish: @MainActor (HotspotPasswordField.Read, (password: String, notice: String?)) -> HotspotPasswordField.ReadAnswer
    ) async {
        var answer = await first()
        var request = request
        while case let .readAgain(next) = finish(request, answer) {
            request = next
            answer = await again()
        }
    }

    static func loadedPassword(_ load: () async throws -> String?) async -> (password: String, notice: String?) {
        do {
            return (try await load() ?? "", nil)
        } catch let error as KeychainError {
            return ("", error.problem.settingsNotice)
        } catch {
            return ("", HotspotPasswordProblem.error(error.localizedDescription).settingsNotice)
        }
    }

    /// Shows a failover report only for the SSID configured now. Otherwise
    /// a quiet Keychain peek explains the actual state without a prompt.
    static func hotspotNotice(
        reported: HotspotPasswordReport?,
        ssid: String,
        reread: () async throws -> String?
    ) async -> String? {
        if let problem = reported?.problem(for: ssid) { return problem.settingsNotice }
        return await loadedPassword(reread).notice
    }

    /// Saves or clears the saved password. The keychain task remains alive
    /// while another section is selected.
    private func savePassword() {
        guard hotspot.startSave() else { return }
        if !HotspotSSID.normalized(manager.config.hotspotSSID).isEmpty {
            locationPermission.requestWhenInUse()
        }
        let password = hotspot.password
        Task {
            let outcome = await Self.storePassword(password, in: secrets)
            let recheck = hotspot.finishSave(outcome, ssid: manager.config.hotspotSSID)
            Self.passwordStored(outcome, configuredSSID: manager.config.hotspotSSID, services: manager.services)
            if let recheck { recheckPassword(recheck) }
        }
    }

    static func passwordStored(_ outcome: HotspotStoreOutcome, configuredSSID: String, services: AppServices?) {
        guard case let .stored(stored) = outcome else { return }
        services?.hotspotPasswordChanged(stored.change, configuredSSID: configuredSSID)
    }

    static func storePassword(_ password: String, in secrets: any HotspotSecretStore) async -> HotspotStoreOutcome {
        do {
            let change = if password.isEmpty {
                try await secrets.delete()
            } else {
                try await secrets.save(password)
            }
            return .stored(.init(ssid: change.ssid, password: password, removed: change.removed))
        } catch {
            Log.error("could not save hotspot password: \(error.localizedDescription)")
            return .failed(notice: "Could not save the hotspot password: \(error.localizedDescription)")
        }
    }
}
