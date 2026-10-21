import SwiftUI

struct NetworkSettingsView: View {
    let manager: SessionManager
    let locationPermission: LocationPermission
    @Binding var hotspot: HotspotPasswordField
    let savePassword: () -> Void

    var body: some View {
        Form {
            Section {
                TextField(L10n.string("Hotspot SSID"), text: SettingsConfigAccess.binding(manager, \.hotspotSSID))

                HStack {
                    SecureField(
                        L10n.string("Hotspot password"),
                        text: Binding(get: { hotspot.password }, set: { hotspot.edit($0) })
                    )
                    .onSubmit(savePassword)

                    Button(L10n.presentation(hotspot.buttonTitle(ssid: manager.config.hotspotSSID)), action: savePassword)
                        .disabled(hotspot.password.isEmpty || hotspot.saving)
                }

                if let notice = hotspot.notice {
                    Text(L10n.presentation(notice))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(L10n.string("Hotspot"))
            } footer: {
                Text(L10n.string("The password is kept in the login keychain, readable without a prompt only by the build of Insomnia that saved it; after a reinstall, enter it again."))
            }

            Section {
                HStack {
                    Text(L10n.format("Location: %@", L10n.string(locationPermission.statusDescription)))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if locationPermission.isDenied {
                        Button(L10n.string("Open Location Services")) {
                            locationPermission.openLocationServicesSettings()
                        }
                    }
                }

                Text(L10n.string("macOS records this grant as Location Services access for Insomnia. Insomnia uses it only to read Wi-Fi network names and never requests your location."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.string("Location Services"))
            } footer: {
                Text(L10n.string("Location permission lets macOS reveal Wi-Fi network names so Insomnia can find the configured hotspot."))
            }
        }
        .formStyle(.grouped)
    }
}
