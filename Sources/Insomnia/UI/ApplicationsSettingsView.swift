import SwiftUI

struct ApplicationsSettingsView: View {
    let manager: SessionManager
    @Binding var newFreezeBundle: String
    @Binding var newAgentBundle: String
    let wouldFreeze: String

    var body: some View {
        Form {
            Section {
                Text(L10n.string("Explicit freeze list"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                BundleIdentifierRows(
                    items: manager.config.freezeList,
                    newValue: $newFreezeBundle,
                    onAdd: { id in
                        SettingsConfigAccess.update(manager) {
                            if !$0.freezeList.contains(id) { $0.freezeList.append(id) }
                        }
                    },
                    onRemove: { id in
                        SettingsConfigAccess.update(manager) {
                            $0.freezeList.removeAll { $0 == id }
                        }
                    }
                )

                Toggle(
                    L10n.string("Freeze every other app while the lid is closed"),
                    isOn: SettingsConfigAccess.binding(manager, \.freezeAllApps)
                )
                Text(L10n.presentation(wouldFreeze))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle(
                    L10n.string("Pause Docker Desktop when no containers are running"),
                    isOn: SettingsConfigAccess.binding(manager, \.dockerRule)
                )
                Text(L10n.string("Off by default. When on, Docker Desktop is paused only if a second check right before the pause still finds no running container; a container that starts in that last moment is paused with it."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.string("Suspend on lid close"))
            } footer: {
                Text(L10n.string("Explicit freeze-list entries are stopped with SIGSTOP while the lid is closed and resumed when it opens, unless the hard denylist excludes them. With Freeze every other app on (off by default), every other Dock app is automatically stopped too, except agent apps, Apple apps, Docker Desktop, and built-in protected apps (editors, terminals, browsers, AI apps, password managers, local databases, Tailscale, local model servers, and meeting, recording, and dictation apps such as Zoom, Teams, Webex, Wispr Flow, Granola, Otter, OBS, and Loom). Agent apps, Apple apps, Insomnia, and Docker Desktop remain excluded even when listed explicitly. Built-in protected apps are excluded from automatic freeze-all; explicitly adding one to the freeze list overrides only that automatic exclusion."))
            }

            Section {
                Text(L10n.string("Agent applications"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                BundleIdentifierRows(
                    items: manager.config.agentList,
                    newValue: $newAgentBundle,
                    onAdd: { id in
                        SettingsConfigAccess.update(manager) {
                            if !$0.agentList.contains(id) { $0.agentList.append(id) }
                        }
                    },
                    onRemove: { id in
                        SettingsConfigAccess.update(manager) {
                            $0.agentList.removeAll { $0 == id }
                        }
                    }
                )

                Toggle(
                    L10n.string("Turn App Nap off for these apps during a session"),
                    isOn: SettingsConfigAccess.binding(manager, \.disableAppNapForAgents)
                )
                Text(L10n.string("Writes NSAppSleepDisabled = YES into each listed app's preferences when a session starts and puts the previous value back when it ends."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.string("Protected/agent applications"))
            } footer: {
                Text(L10n.string("Agent apps are never frozen or throttled. Editors, AI apps, terminals, browsers, password managers, local databases, Tailscale, local model servers, and meeting, recording and dictation apps are also protected from the automatic lid-close scope even when they are not listed here; adding one to the freeze list above overrides that built-in automatic protection. The hard denylist still prevents explicit freezing of agent apps, Apple apps, Insomnia and Docker Desktop."))
            }
        }
        .formStyle(.grouped)
    }
}
