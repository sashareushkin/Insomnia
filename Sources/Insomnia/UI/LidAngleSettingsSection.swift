import SwiftUI

struct LidAngleSettingsSection: View {
    let manager: SessionManager
    let automation: LidAutomationController

    var body: some View {
        Section(L10n.string("Lid angle automation")) {
            Toggle(
                L10n.string("Automatically start and end Insomnia"),
                isOn: SettingsConfigAccess.binding(manager, \.lidAngleEnabled)
            )
            Stepper(value: SettingsConfigAccess.binding(manager, \.lidAngleThresholds.close),
                    in: manager.config.lidAngleThresholds.closeRange) {
                LabeledContent(L10n.string("Start while closing"), value: degrees(manager.config.lidAngleThresholds.close))
            }
            Stepper(value: SettingsConfigAccess.binding(manager, \.lidAngleThresholds.open),
                    in: manager.config.lidAngleThresholds.openRange) {
                LabeledContent(L10n.string("End while opening"), value: degrees(manager.config.lidAngleThresholds.open))
            }
            Text(L10n.string("Starts a session for the default timer duration. Opening the lid ends only a session started by lid angle automation."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        Section(L10n.string("Lid angle diagnostics")) {
            Toggle(
                L10n.string("Monitor the sensor for diagnostics"),
                isOn: Binding(get: { automation.diagnosticsEnabled }, set: { automation.setDiagnosticsEnabled($0) })
            )
            LabeledContent(L10n.string("Lid angle sensor"), value: status(automation.monitor.diagnostics.status))
            if automation.diagnosticsEnabled {
                details(automation.monitor.diagnostics)
            }
        }
    }

    @ViewBuilder
    private func details(_ diagnostics: LidDiagnostics) -> some View {
        if let state = diagnostics.state {
            LabeledContent(L10n.string("Current angle"), value: degrees(Int(state.angle)))
            LabeledContent(L10n.string("Direction"), value: direction(state.direction))
            LabeledContent(L10n.string("Angular speed"), value: L10n.format("%@°/s", number(abs(state.speed))))
        }
        if let rate = diagnostics.readingsPerSecond {
            LabeledContent(L10n.string("Successful reads per second"), value: number(rate))
        }
        if let rate = diagnostics.changesPerSecond {
            LabeledContent(L10n.string("Angle changes per second"), value: number(rate))
        }
        LabeledContent(L10n.string("Read errors"), value: diagnostics.readErrors.formatted())
        if let lastRead = diagnostics.lastRead {
            LabeledContent(L10n.string("Last successful read"), value: lastRead.formatted(date: .omitted, time: .standard))
        }
    }

    private func status(_ status: LidMonitorStatus) -> String {
        switch status {
        case .stopped: L10n.string("Monitoring off")
        case .waiting: L10n.string("Looking for the sensor…")
        case .suspended: L10n.string("Paused for system sleep")
        case .available: L10n.string("Available")
        case .unavailable(.notFound): L10n.string("No supported lid angle sensor found")
        case .unavailable(.invalidReport): L10n.string("Unrecognized report · retrying")
        case let .unavailable(.openFailed(code)):
            L10n.format("Could not open the sensor (%@) · retrying", hex(code))
        case let .unavailable(.readFailed(code)):
            L10n.format("Could not read the sensor (%@) · retrying", hex(code))
        }
    }

    private func direction(_ direction: LidDirection) -> String {
        switch direction {
        case .unknown: L10n.string("Detecting…")
        case .stationary: L10n.string("Stationary")
        case .opening: L10n.string("Opening")
        case .closing: L10n.string("Closing")
        }
    }

    private func degrees(_ value: Int) -> String {
        L10n.format("%@°", value.formatted())
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func hex(_ code: Int32) -> String {
        String(format: "0x%08X", UInt32(bitPattern: code))
    }
}
