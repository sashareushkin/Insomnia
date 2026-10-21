import SwiftUI

struct TimerSettingsView: View {
    let manager: SessionManager
    @Binding var newPreset: String
    @Binding var presetError: String?

    var body: some View {
        Form {
            Section(L10n.string("Duration presets")) {
                ForEach(manager.config.presets, id: \.self) { preset in
                    HStack {
                        Text(chipLabel(for: preset))
                            .monospacedDigit()
                        Spacer(minLength: 8)
                        if preset == manager.config.defaultPreset {
                            Text(L10n.string("default"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        SettingsRemoveButton(label: L10n.format("Remove preset %@", chipLabel(for: preset))) {
                            SettingsConfigAccess.update(manager) {
                                $0.presets.removeAll { $0 == preset }
                            }
                        }
                    }
                }

                HStack {
                    TextField(L10n.string("Add preset (30m, 2h, 1h30m, 3d)"), text: $newPreset)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addPreset)
                    Button(L10n.string("Add"), action: addPreset)
                        .disabled(DurationParser.seconds(from: newPreset) == nil)
                }

                if let presetError {
                    Text(L10n.presentation(presetError))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(L10n.string("Session defaults")) {
                Picker(L10n.string("Default preset"), selection: SettingsConfigAccess.binding(manager, \.defaultPreset)) {
                    ForEach(manager.config.presets, id: \.self) { preset in
                        Text(chipLabel(for: preset)).tag(preset)
                    }
                    if !manager.config.presets.contains(manager.config.defaultPreset) {
                        Text(chipLabel(for: manager.config.defaultPreset)).tag(manager.config.defaultPreset)
                    }
                }

                Picker(L10n.string("Default field"), selection: SettingsConfigAccess.binding(manager, \.defaultFocusField)) {
                    ForEach(DurationInput.Field.allCases, id: \.self) { field in
                        Text(L10n.string(field.placeholder)).tag(field)
                    }
                }
                .help(L10n.string("The pill that is focused when the pills open"))

                LabeledContent(L10n.string("Maximum session")) {
                    Text(chipLabel(for: manager.config.maxDuration))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func addPreset() {
        guard let seconds = DurationParser.seconds(from: newPreset) else { return }
        guard seconds <= manager.config.maxDuration else {
            presetError = L10n.format("Presets cannot exceed %@.", chipLabel(for: manager.config.maxDuration))
            return
        }
        presetError = nil
        SettingsConfigAccess.update(manager) {
            if !$0.presets.contains(seconds) {
                $0.presets.append(seconds)
                $0.presets.sort()
            }
        }
        newPreset = ""
    }
}
