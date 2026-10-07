import AppKit
import GalenoCore
import SwiftUI

/// Ajustes (⌘,): apariencia, menos movimiento, los sonidos, el grano y las actualizaciones. Nada de esto sale
/// de la máquina ni cambia lo que el agente puede hacer.
struct SettingsView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var updates: UpdatesModel
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

            VStack(alignment: .leading, spacing: 6) {
                SmallCapsLabel("settings.updates", size: 13)
                    .foregroundStyle(Color.ink700)
                Text(verbatim: Localized.string("settings.updates.version %@", UpdatesModel.version, locale: locale))
                    .font(Typo.text(15))
                    .foregroundStyle(Color.ink900)
                    .textSelection(.enabled)
                if updates.isEnabled {
                    Button("settings.updates.check") { updates.checkForUpdates() }
                        .buttonStyle(LinkTextStyle())
                        .disabled(!updates.canCheck)
                } else {
                    // Dicho tal cual: una compilación sin appcast no se va a actualizar sola.
                    Text("settings.updates.off")
                        .font(Typo.text(13))
                        .foregroundStyle(Color.ink500)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
