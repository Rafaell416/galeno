import AppKit
import GalenoCore
import SwiftUI

/// Ajustes (⌘,): apariencia, menos movimiento, los sonidos y el grano. Nada de esto sale
/// de la máquina ni cambia lo que el agente puede hacer.
struct SettingsView: View {
    @ObservedObject var app: AppModel
    @AppStorage(Prefs.appearance) private var appearance = AppearanceChoice.system.rawValue
    @AppStorage(Prefs.reduceMotion) private var reduceMotion = false
    @AppStorage(Prefs.sounds) private var sounds = true
    @AppStorage(Grain.defaultsKey) private var grain = true
    @Environment(\.locale) private var locale

    private var choice: Binding<AppearanceChoice> {
        Binding(
            get: { AppearanceChoice(rawValue: appearance) ?? .system },
            set: {
                appearance = $0.rawValue
                $0.apply()
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(text: Text("settings.title"))

            VStack(alignment: .leading, spacing: 8) {
                SmallCapsLabel("settings.appearance", size: 13)
                    .foregroundStyle(Color.ink700)
                InkSegmented(selection: choice, options: AppearanceChoice.allCases, padding: 16, fontSize: 15) { option in
                    Text(LocalizedStringKey("settings.appearance." + option.rawValue))
                }
                .accessibilityLabel(Text("settings.appearance"))
            }

            VStack(alignment: .leading, spacing: 14) {
                row("settings.motion", "settings.motion.hint", isOn: $reduceMotion)
                row("settings.sound", "settings.sound.hint", isOn: $sounds)
                row("settings.grain", "settings.grain.hint", isOn: $grain)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(width: 460, alignment: .topLeading)
        .background(Color.parchment50)
        .motionPreference()
        .environment(\.locale, Locale(identifier: app.language.rawValue))
    }

    private func row(_ title: LocalizedStringKey, _ hint: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.text(15, .medium)).foregroundStyle(Color.ink900)
                Text(hint)
                    .font(Typo.text(13))
                    .foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.inkCheckbox)
    }
}
