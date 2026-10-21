import SwiftUI

struct TmuxSettingsView: View {
    let manager: SessionManager
    @Binding var newTarget: String

    var body: some View {
        Form {
            Section {
                Stepper(value: nudgeSeconds, in: 10...900, step: 10) {
                    LabeledContent(
                        L10n.string("Nudge tmux after"),
                        value: L10n.format("%d s offline", Int(manager.config.nudgeThreshold))
                    )
                }

                Text(L10n.string("After that long offline, Insomnia types \"continue\" into each pane listed below. Only a pane you have marked with this tmux command is nudged. Mark a dedicated pane, not one you type in."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(TmuxNudge.markCommand())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Toggle(
                    L10n.string("Press Enter after continue"),
                    isOn: SettingsConfigAccess.binding(manager, \.tmuxNudgePressesEnter)
                )
                Text(L10n.string("Enter submits whatever is already typed in that pane, including a line that was never finished. When off, \"continue\" is typed and nothing submits it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(manager.config.tmuxTargets, id: \.self) { target in
                    HStack {
                        Text(target)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        SettingsRemoveButton(label: L10n.format("Remove tmux target %@", target)) {
                            SettingsConfigAccess.update(manager) {
                                $0.tmuxTargets.removeAll { $0 == target }
                            }
                        }
                    }
                }

                TextField(L10n.string("tmux target (session:window.pane)"), text: $newTarget)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTarget)
                Button(L10n.string("Add"), action: addTarget)
                    .disabled(newTarget.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text(L10n.string("Reconnect nudges"))
            } footer: {
                Text(L10n.string("This action only targets panes marked with the command above. With Enter enabled, it can submit unfinished input in a marked pane."))
            }
        }
        .formStyle(.grouped)
    }

    private var nudgeSeconds: Binding<Int> {
        Binding(
            get: { Int(manager.config.nudgeThreshold) },
            set: { seconds in
                SettingsConfigAccess.update(manager) { $0.nudgeThreshold = TimeInterval(seconds) }
            }
        )
    }

    private func addTarget() {
        let target = newTarget.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return }
        SettingsConfigAccess.update(manager) {
            if !$0.tmuxTargets.contains(target) { $0.tmuxTargets.append(target) }
        }
        newTarget = ""
    }
}
