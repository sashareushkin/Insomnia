import AppKit
import SwiftUI

/// Shared access to the existing config model. Every binding still writes
/// through immediately and persists by the same manager/store path.
@MainActor
enum SettingsConfigAccess {
    static func binding<Value: Equatable>(
        _ manager: SessionManager,
        _ keyPath: WritableKeyPath<Config, Value>
    ) -> Binding<Value> {
        Binding(
            get: { manager.config[keyPath: keyPath] },
            set: { value in
                guard manager.config[keyPath: keyPath] != value else { return }
                manager.config[keyPath: keyPath] = value
                save(manager)
            }
        )
    }

    static func update(_ manager: SessionManager, _ change: (inout Config) -> Void) {
        var config = manager.config
        change(&config)
        guard config != manager.config else { return }
        manager.config = config
        save(manager)
    }

    private static func save(_ manager: SessionManager) {
        do {
            try manager.store.saveConfig(manager.config)
        } catch {
            Log.error("could not save config: \(error.localizedDescription)")
        }
    }
}

struct SettingsRemoveButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle.fill")
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Native rows for the explicit freeze and protected-app lists.
struct BundleIdentifierRows: View {
    let items: [String]
    @Binding var newValue: String
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        ForEach(items, id: \.self) { id in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(RunningApps.displayName(for: id))
                    Text(id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                SettingsRemoveButton(label: L10n.format("Remove %@", RunningApps.displayName(for: id))) {
                    onRemove(id)
                }
            }
        }

        TextField(L10n.string("Bundle identifier"), text: $newValue)
            .textFieldStyle(.roundedBorder)
            .onSubmit(addTypedBundle)

        HStack {
            Button(L10n.string("Add"), action: addTypedBundle)
                .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
            Menu(L10n.string("Add running app…")) {
                let apps = RunningApps.candidates(excluding: items)
                if apps.isEmpty {
                    Text(L10n.string("No other apps running"))
                }
                ForEach(apps, id: \.bundleID) { app in
                    Button(app.name) { onAdd(app.bundleID) }
                }
            }
        }
    }

    private func addTypedBundle() {
        let value = newValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        onAdd(value)
        newValue = ""
    }
}

/// Running apps offered by "Add running app…": everything with a bundle id
/// that is not Apple's own.
@MainActor
enum RunningApps {
    struct Entry: Hashable {
        let bundleID: String
        let name: String
    }

    static func candidates(excluding: [String]) -> [Entry] {
        let me = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var out: [Entry] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, !id.hasPrefix("com.apple."), id != me,
                  app.activationPolicy != .prohibited,
                  !excluding.contains(id), !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(Entry(bundleID: id, name: app.localizedName ?? id))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Name of a running app for a bundle id, or the last path component.
    static func displayName(for bundleID: String) -> String {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = app.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
