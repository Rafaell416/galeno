import AppKit
import SwiftUI

/// Las preferencias de la app (Ajustes, ⌘,). Viven en `UserDefaults`; ninguna sale de la máquina.
enum Prefs {
    static let appearance = "GalenoAppearance"
    static let reduceMotion = "GalenoReduceMotion"
    /// Los tres sonidos (`Sounds`). Sin valor guardado cuentan como encendidos.
    static let sounds = "GalenoSoundsEnabled"
    static let splashShown = "GalenoSplashShown"
}

/// Cómo se ve la app: la del sistema, siempre clara o siempre oscura.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// `nil` deja que mande el sistema.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var stored: AppearanceChoice {
        AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: Prefs.appearance) ?? "") ?? .system
    }

    /// Los tokens de `Theme.swift` son `NSColor` dinámicos: cambiar la apariencia de la app basta.
    @MainActor
    func apply() {
        NSApp.appearance = nsAppearance
    }
}

// MARK: - Menos movimiento

private struct GalenoReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// «Reducir movimiento» del sistema **o** «Menos movimiento» de Ajustes (para quien no toca el
    /// del sistema). Todo el movimiento de la app lee esta y no la del sistema.
    var galenoReduceMotion: Bool {
        get { self[GalenoReduceMotionKey.self] }
        set { self[GalenoReduceMotionKey.self] = newValue }
    }
}

private struct MotionPreference: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var system
    @AppStorage(Prefs.reduceMotion) private var stored = false

    func body(content: Content) -> some View {
        content.environment(\.galenoReduceMotion, system || stored)
    }
}

extension View {
    /// Se pone una vez en la raíz de cada ventana.
    func motionPreference() -> some View { modifier(MotionPreference()) }
}
