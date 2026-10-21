import Foundation

/// Stable identities for the Settings sidebar. Titles are localized at the
/// view boundary and never participate in selection or destination routing.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case timer
    case lidClose
    case applications
    case power
    case network
    case tmux

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .general: "General"
        case .timer: "Timer"
        case .lidClose: "Lid Close"
        case .applications: "Applications"
        case .power: "Power"
        case .network: "Network"
        case .tmux: "tmux"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .timer: "timer"
        case .lidClose: "laptopcomputer"
        case .applications: "square.stack.3d.up"
        case .power: "battery.100percent"
        case .network: "wifi"
        case .tmux: "terminal"
        }
    }

    var destination: SettingsDestination {
        switch self {
        case .general: .general
        case .timer: .timer
        case .lidClose: .lidClose
        case .applications: .applications
        case .power: .power
        case .network: .network
        case .tmux: .tmux
        }
    }
}

/// Destination map kept separate from localized row titles so navigation
/// identity and view routing can be checked independently.
enum SettingsDestination: Equatable {
    case general
    case timer
    case lidClose
    case applications
    case power
    case network
    case tmux
}
