import SwiftUI

struct SettingsView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = preferences

        NavigationStack {
            Form {
                Section(String(localized: "settings.section.mode")) {
                    Picker(String(localized: "settings.mode.label"), selection: $preferences.userMode) {
                        Text(String(localized: "mode.beginner.title")).tag(UserMode.beginner)
                        Text(String(localized: "mode.expert.title")).tag(UserMode.expert)
                    }
                }
                Section(String(localized: "settings.section.measurement")) {
                    Toggle(String(localized: "settings.silent_mode_default"), isOn: $preferences.silentModeDefault)
                }
                Section(String(localized: "settings.section.help")) {
                    NavigationLink(String(localized: "settings.glossary"), destination: GlossaryView())
                }
                Section(String(localized: "settings.section.about")) {
                    LabeledContent(String(localized: "settings.version"), value: "0.1.0")
                    LabeledContent(String(localized: "settings.bundle_id"), value: "com.ticklab.watchaccuracypro")
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
    }
}

struct GlossaryView: View {
    private let entries: [(key: String, descKey: String)] = [
        ("glossary.bph", "glossary.bph.desc"),
        ("glossary.rate", "glossary.rate.desc"),
        ("glossary.beat_error", "glossary.beat_error.desc"),
        ("glossary.amplitude", "glossary.amplitude.desc"),
        ("glossary.cosc", "glossary.cosc.desc"),
        ("glossary.lift_angle", "glossary.lift_angle.desc"),
        ("glossary.coaxial", "glossary.coaxial.desc")
    ]

    var body: some View {
        List {
            ForEach(entries, id: \.key) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: String.LocalizationValue(entry.key)))
                        .font(AppTypography.headline)
                    Text(String(localized: String.LocalizationValue(entry.descKey)))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(String(localized: "glossary.title"))
    }
}

#Preview {
    SettingsView().environment(UserPreferences())
}
