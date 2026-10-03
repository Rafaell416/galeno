import Combine
import Foundation
import GalenoCore

/// Todo lo que el wizard va capturando. Al final, `makeConfig()` lo convierte
/// en el `AgentConfig` que se le pasa al motor.
///
/// Es la única fuente de verdad: las pantallas leen y escriben aquí, y la
/// navegación también. No contiene credenciales (igual que `AgentConfig`).
@MainActor
final class WizardState: ObservableObject {
    @Published private(set) var step: WizardStep = .welcome

    // MARK: Lo que captura el wizard

    @Published var language: Language
    @Published var agentName = ""
    @Published var projectDescription = ""
    @Published var connections: [ToolConnection] = []
    @Published var skills: [SelectedSkill] = []
    @Published var sendingRules: SendingRules = .default

    /// - Parameter preferredLanguages: los idiomas del Mac, en orden de
    ///   preferencia. Inyectable para las pruebas.
    init(preferredLanguages: [String] = Locale.preferredLanguages) {
        language = Self.defaultLanguage(from: preferredLanguages)
    }

    /// El idioma del paso 1 viene preseleccionado según el Mac: español si el
    /// primero de sus idiomas es español, inglés en cualquier otro caso.
    nonisolated static func defaultLanguage(from preferredLanguages: [String]) -> Language {
        guard let first = preferredLanguages.first?.lowercased() else { return .english }
        return first == "es" || first.hasPrefix("es-") || first.hasPrefix("es_") ? .spanish : .english
    }

    // MARK: Navegación

    var stepCount: Int { WizardStep.allCases.count }

    /// De 1/10 en el primer paso a 1 en el último: la barra se ve desde el
    /// principio y se llena del todo en "Listo".
    var progress: Double { Double(step.number) / Double(stepCount) }

    var isFirstStep: Bool { step == WizardStep.allCases.first }
    var isLastStep: Bool { step == WizardStep.allCases.last }

    var canGoBack: Bool { step.allowsGoingBack }
    var canGoForward: Bool { !isLastStep }

    func next() {
        guard canGoForward, let following = WizardStep(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    func back() {
        guard canGoBack, let previous = WizardStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: El resultado

    /// El `AgentConfig` con el que se genera la carpeta del agente.
    func makeConfig() -> AgentConfig {
        AgentConfig(
            agentName: agentName.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language,
            role: .productManager,
            projectDescription: projectDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            connections: connections,
            skills: skills,
            sendingRules: sendingRules
        )
    }
}
