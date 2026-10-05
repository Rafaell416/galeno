import AppKit
import SwiftUI

/// Las preferencias de la app (Ajustes, ⌘,). Viven en `UserDefaults`; ninguna sale de la máquina.
enum Prefs {
    static let appearance = "GalenoAppearance"
    static let reduceMotion = "GalenoReduceMotion"
    /// Los tres sonidos (`Sounds`). Sin valor guardado cuentan como encendidos.
    static let sounds = "GalenoSoundsEnabled"
    static let splashShown = "GalenoSplashShown"
    /// Las tres pantallas de antes del asistente ya se vieron (o se saltaron): no vuelven.
    static let onboardingSeen = "GalenoOnboardingSeen"
    /// Dónde abre el home un agente: la app de Claude o Terminal (la última elección).
    static let openTarget = "GalenoOpenTarget"
    /// Cuándo cambió «Gestionar» las herramientas de cada agente (id → segundos Unix). Una conversación que la
    /// app de Claude tenga abierta desde antes no las ve: al abrir ese agente, Claude se reinicia.
    static let toolsChangedAt = "GalenoAgentToolsChangedAt"
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

// MARK: - Terminar el wizard

private struct FinishWizardKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    /// Qué hace «Terminar» en el último paso. Con el home, vuelve a él; sin él (pruebas, vista previa),
    /// el wizard cierra la app como antes.
    var galenoFinishWizard: (@MainActor () -> Void)? {
        get { self[FinishWizardKey.self] }
        set { self[FinishWizardKey.self] = newValue }
    }
}

private struct CancelWizardKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    /// «Cancelar» en el primer paso del wizard corto: vuelve al home sin crear nada.
    var galenoCancelWizard: (@MainActor () -> Void)? {
        get { self[CancelWizardKey.self] }
        set { self[CancelWizardKey.self] = newValue }
    }
}
