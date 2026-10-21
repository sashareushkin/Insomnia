import SwiftUI

struct LidCloseSettingsView: View {
    let manager: SessionManager

    var body: some View {
        Form {
            if let notice = manager.config.lidCloseDefaultsNotice {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.presentation(notice.settingsLine))
                            .font(.callout)
                        Spacer(minLength: 8)
                        Button(L10n.string("Dismiss")) { manager.dismissLidCloseNotice() }
                    }
                }
            }

            Section(L10n.string("Display and keyboard")) {
                Toggle(
                    L10n.string("Turn off the display and keyboard backlight"),
                    isOn: SettingsConfigAccess.binding(manager, \.darkenDisplayOnLidClose)
                )
                ForEach(manager.darkenRefusals, id: \.self) { reason in
                    Text(L10n.presentation(reason))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(L10n.string("The display brightness and keyboard backlight are saved, set to zero and restored when the lid opens. If Insomnia is not running when you open the lid, press the brightness-up key."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("Audio")) {
                Toggle(
                    L10n.string("Mute audio on lid close"),
                    isOn: SettingsConfigAccess.binding(manager, \.muteOnLidClose)
                )
                Text(L10n.string(SettingsView.microphoneNote))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.string("Lid-close power")) {
                Toggle(
                    L10n.string("Low Power Mode while the lid is closed"),
                    isOn: SettingsConfigAccess.binding(manager, \.lowPowerOnLidClose)
                )
                // A floor input: apply it immediately if the lid is already closed.
                .onChange(of: manager.config.lowPowerOnLidClose) {
                    manager.services?.reevaluateFloors()
                }
            }
        }
        .formStyle(.grouped)
    }
}
