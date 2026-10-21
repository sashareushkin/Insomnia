import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    let manager: SessionManager
    let localization: LocalizationManager
    let loginItem: LoginItem
    let releases: ReleaseChecker

    var body: some View {
        Form {
            Section(L10n.string("Language")) {
                Picker(L10n.string("Language"), selection: Binding(
                    get: { localization.language },
                    set: { localization.language = $0 }
                )) {
                    Text("Русский").tag(AppLanguage.russian)
                    Text("English").tag(AppLanguage.english)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityLabel(L10n.string("Language"))

                Text(L10n.string("Insomnia selects its language from macOS settings each time it starts. Your choice here lasts until the app exits."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("App")) {
                Toggle(L10n.string("Launch at login"), isOn: launchAtLogin)
                loginItemNote

                LabeledContent(L10n.string("Config")) {
                    Text(manager.paths.configFile.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent(L10n.string("Version")) {
                    Text(L10n.presentation(AppBuild.current.label))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                releaseCheck

                if LidSimulationBuild.isCompiledIn {
                    Text(L10n.presentation(LidSimulationBuild.marker))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// This is the state macOS reports, including a registration awaiting
    /// approval. Failed changes leave the prior configuration in place.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { loginItem.isRegistered },
            set: { on in
                SettingsConfigAccess.update(manager) { config in
                    _ = loginItem.set(on, config: &config)
                }
            }
        )
    }

    @ViewBuilder
    private var loginItemNote: some View {
        if let error = loginItem.error {
            Text(L10n.format("Login item: %@", L10n.presentation(error)))
                .font(.caption)
                .foregroundStyle(.red)
        } else if loginItem.needsApproval {
            HStack {
                Text(L10n.string("Waiting for approval in System Settings > General > Login Items. Turn the switch off to withdraw it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(L10n.string("Open Login Items")) { loginItem.openLoginItems() }
            }
        } else if manager.config.launchAtLogin, !loginItem.isRegistered {
            Text(L10n.format("Login item: macOS reports it %@. Turn the switch on to register it again.", L10n.presentation(loginItem.status.description)))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// The update check only reads GitHub's releases list; it installs
    /// nothing and retains the checker's idle, in-flight and result states.
    @ViewBuilder
    private var releaseCheck: some View {
        HStack {
            Button(L10n.string(releases.state == .checking ? "Checking" : "Check for updates")) {
                releases.check()
            }
            .disabled(releases.state == .checking)

            Button(L10n.string("Open releases page")) {
                NSWorkspace.shared.open(GitHubReleaseFetcher.releasesPage)
            }
        }

        switch releases.state {
        case .idle:
            Text(L10n.string("Asks GitHub when you click, and installs nothing. To upgrade, run the installer again."))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            EmptyView()
        case let .checked(report):
            Text(L10n.presentation(report.summary))
                .font(.caption)
                .foregroundStyle(report.standing == .newerStableAvailable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .textSelection(.enabled)
        case let .failed(reason):
            Text(L10n.format("Could not check: %@", L10n.presentation(reason)))
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
