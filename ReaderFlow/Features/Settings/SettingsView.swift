import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [ReaderSettingsEntity]

    var body: some View {
        Group {
            if let activeSettings = settings.first {
                settingsForm(activeSettings)
            } else {
                ProgressView()
                    .onAppear(ensureSettings)
            }
        }
        .navigationTitle("Settings")
    }

    private func settingsForm(_ activeSettings: ReaderSettingsEntity) -> some View {
        Form {
            Section("Reading") {
                Picker("Theme", selection: binding(activeSettings, \.theme)) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.rawValue.capitalized).tag(theme.rawValue)
                    }
                }

                Picker("Font", selection: binding(activeSettings, \.fontFamily)) {
                    ForEach(ReaderFontFamily.allCases) { font in
                        Text(font.displayName).tag(font.rawValue)
                    }
                }

                LabeledContent("Text Size") {
                    Stepper(
                        value: binding(activeSettings, \.textSize),
                        in: 14 ... 30,
                        step: 1
                    ) {
                        Text("\(Int(activeSettings.textSize))")
                            .monospacedDigit()
                    }
                }

                LabeledContent("Line Height") {
                    Stepper(
                        value: binding(activeSettings, \.lineHeight),
                        in: 1.2 ... 2.0,
                        step: 0.05
                    ) {
                        Text(activeSettings.lineHeight, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                }

                LabeledContent("Speed") {
                    Stepper(value: binding(activeSettings, \.autoscrollSpeed), in: 5 ... 120, step: 5) {
                        Text("\(Int(activeSettings.autoscrollSpeed))")
                            .monospacedDigit()
                    }
                }
            }

            Section("Excerpts") {
                Toggle("Auto-copy saved excerpts", isOn: binding(activeSettings, \.autoCopyHighlights))
                Toggle("Haptic confirmation", isOn: binding(activeSettings, \.hapticsEnabled))
            }
        }
    }

    private func ensureSettings() {
        guard settings.isEmpty else { return }
        modelContext.insert(ReaderSettingsEntity())
        try? modelContext.save()
    }

    private func binding<T>(
        _ activeSettings: ReaderSettingsEntity,
        _ keyPath: ReferenceWritableKeyPath<ReaderSettingsEntity, T>
    ) -> Binding<T> {
        Binding(
            get: { activeSettings[keyPath: keyPath] },
            set: { newValue in
                activeSettings[keyPath: keyPath] = newValue
                try? modelContext.save()
            }
        )
    }
}
