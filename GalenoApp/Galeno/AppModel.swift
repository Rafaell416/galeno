import Combine
import Foundation
import GalenoCore

/// Qué muestra la ventana: el home (ya hay agentes) o el wizard (la primera vez, o «Nuevo agente»).
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable { case home, wizard }

    @Published private(set) var screen: Screen
    @Published private(set) var wizard: WizardState
    /// El idioma de la ventana y de Ajustes: el del wizard mientras se usa, el de la instalación en el home.
    @Published private(set) var language: Language
    let home: HomeModel

    private let makeWizard: @MainActor ([String]) -> WizardState
    private let makeShortWizard: @MainActor (GalenoInstallation) -> WizardState
    private let makeEditWizard: @MainActor (GalenoInstallation, UUID) -> WizardState
    private var wizardObserver: AnyCancellable?
    private var languageObserver: AnyCancellable?

    init(
        home: HomeModel = HomeModel(),
        makeWizard: @escaping @MainActor ([String]) -> WizardState = {
            WizardState(preferredLanguages: $0, draftStore: FileDraftStore())
        },
        makeShortWizard: @escaping @MainActor (GalenoInstallation) -> WizardState = {
            WizardState(preferredLanguages: [$0.language.rawValue], startingFrom: $0)
        },
        makeEditWizard: @escaping @MainActor (GalenoInstallation, UUID) -> WizardState = {
            WizardState(preferredLanguages: [$0.language.rawValue], startingFrom: $0, editing: $1)
        }
    ) {
        self.home = home
        self.makeWizard = makeWizard
        self.makeShortWizard = makeShortWizard
        self.makeEditWizard = makeEditWizard
        let wizard = makeWizard(Locale.preferredLanguages)
        self.wizard = wizard

        // Un borrador sin terminar manda (su pantalla «¿Seguimos?»); si no, hay agentes → home, y un
        // `installation.json` ilegible también va al home, que lo dice, en vez de al wizard.
        let hasAgents: Bool
        switch home.state {
        case .agents, .unreadable: hasAgents = true
        case .empty: hasAgents = false
        }
        if wizard.pendingDraft == nil, hasAgents {
            screen = .home
            language = home.language
        } else {
            screen = .wizard
            language = wizard.language
        }
        observe(wizard)
    }

    /// «Nuevo agente»: el wizard corto (`docs/03` §3b). Parte de lo que la instalación ya tiene —idioma y
    /// herramientas conectadas— y solo pide conectar lo que el proyecto use y todavía no esté. Si la instalación
    /// no se puede leer no se crea nada.
    func startNewAgent() {
        guard let installation = home.loadInstallation() else { return }
        wizard.stopWorking()
        let fresh = makeShortWizard(installation)
        wizard = fresh
        observe(fresh)
        language = fresh.language
        screen = .wizard
    }

    /// «Gestionar»: las pantallas del wizard con lo que el agente ya tiene, para cambiar qué lee, sus skills y sus
    /// reglas. Al guardar se regenera **su** carpeta (`docs/03` §3b) y se vuelve al home. Si la instalación no se
    /// puede leer, o el agente ya no está en ella, no se hace nada.
    func manageAgent(_ id: UUID) {
        guard let installation = home.loadInstallation(), installation.agent(id: id) != nil else { return }
        wizard.stopWorking()
        let fresh = makeEditWizard(installation, id)
        fresh.onSaved = { [weak self] in self?.finishWizard() }
        wizard = fresh
        observe(fresh)
        language = fresh.language
        screen = .wizard
    }

    /// Se eliminó un agente desde el home. Si era el último, no hay nada que listar: se abre el wizard corto, que
    /// parte de las conexiones que ya están hechas.
    func agentRemoved() {
        if case .agents = home.state { return }
        guard case .empty = home.state else { return }
        startNewAgent()
    }

    /// «Cancelar» en el primer paso del wizard corto: de vuelta al home, sin haber creado nada.
    func cancelWizard() {
        wizard.stopWorking()
        language = home.language
        screen = .home
    }

    /// «Terminar» en el último paso del wizard: de vuelta al home, con el agente nuevo en la lista.
    func finishWizard() {
        wizard.stopWorking()
        home.reload()
        language = home.language
        screen = .home
    }

    private func observe(_ wizard: WizardState) {
        // El menú «Paso» lee el wizard actual: que cambie algo suyo vuelve a pintar la app.
        wizardObserver = wizard.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        languageObserver = wizard.$language.dropFirst().sink { [weak self] language in
            guard let self, screen == .wizard else { return }
            self.language = language
        }
    }
}
