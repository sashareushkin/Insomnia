import SwiftUI

struct PowerSettingsView: View {
    let manager: SessionManager

    var body: some View {
        Form {
            Section(L10n.string("Battery and thermal")) {
                Stepper(value: lowPowerFloor, in: 0...100, step: Config.floorStep) {
                    LabeledContent(L10n.string("Low Power Mode below"), value: "\(manager.config.lowPowerFloor)%")
                }
                Stepper(value: endFloor, in: 0...Config.maxEndFloor, step: Config.floorStep) {
                    LabeledContent(L10n.string("End session below"), value: "\(manager.config.endFloor)%")
                }
                Text(L10n.string("0 turns the battery end off. The end floor stays below the Low Power Mode floor. Moving one onto the other moves it along."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(
                    L10n.string("Thermal rules (Low Power Mode when hot, end when critical)"),
                    isOn: SettingsConfigAccess.binding(manager, \.thermalRules)
                )
            }
        }
        .formStyle(.grouped)
    }

    private var lowPowerFloor: Binding<Int> {
        Binding(
            get: { manager.config.lowPowerFloor },
            set: { value in SettingsConfigAccess.update(manager) { $0.setLowPowerFloor(value) } }
        )
    }

    private var endFloor: Binding<Int> {
        Binding(
            get: { manager.config.endFloor },
            set: { value in SettingsConfigAccess.update(manager) { $0.setEndFloor(value) } }
        )
    }
}
