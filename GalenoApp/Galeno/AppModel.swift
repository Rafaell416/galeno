import Combine
import Foundation
import GalenoCore

/// Qué muestra la ventana: el home (ya hay agentes), el detalle de un agente, o el wizard (la primera vez, o «Nuevo agente»).
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable { case home, wizard, health, agent }

    @Published private(set) var screen: Screen
    @Published private(set) var wizard: WizardState
    /// El idioma de la ventana y de Ajustes: el del wizard mientras se usa, el de la instalación en el home.
    @Published private(set) var language: Language
    let home: HomeModel
    /// La vista de salud, mientras está abierta (se crea al entrar y se suelta al salir).
    @Published private(set) var health: HealthModel?
    /// El detalle del agente, mientras está abierto (se crea al entrar y se suelta al salir).
    @Published private(set) var agentDetail: AgentDetailModel?

    private let makeHealth: @MainActor (Language) -> HealthModel
    private let makeAgentDetail: @MainActor (UUID, AgentDetailModel.Section, HomeModel, Language) -> AgentDetailModel
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
        },
        makeHealth: @escaping @MainActor (Language) -> HealthModel = { language in
            // El home le da después con qué activar el envío por WhatsApp (`openHealth`).
            HealthModel(accountBridge: { WhatsAppBridge.live(account: $0) }, language: { language })
        },
        makeAgentDetail: @escaping @MainActor (UUID, AgentDetailModel.Section, HomeModel, Language) -> AgentDetailModel = {
            id, section, home, language in
            // La misma instalación que lee el home: lo que el detalle cambia, el home lo ve.
            var installer = AgentInstaller.live()
            installer.store = home.store
            return AgentDetailModel(
                agentID: id, section: section, home: home,
                health: HealthModel(
                    store: home.store, installer: installer,
                    agentsChanged: { agents in agents.forEach { home.noteToolsChanged($0) } },
                    accountBridge: { WhatsAppBridge.live(account: $0) },
                    language: { language }),
                installer: installer,
                makeAccountPicker: { installation, agentID, account in
                    // Otro número de WhatsApp: el asistente que hospeda el QR lleva su propio puente (`--account`).
                    var services = ConnectServices.live()
                    services.whatsapp = WhatsAppBridge.live(account: account)
                    return WizardState(
                        preferredLanguages: [installation.language.rawValue], connectServices: services,
                        startingFrom: installation, editing: agentID)
                },
                numberBridge: { WhatsAppBridge.live(account: $0) })
        }
    ) {
        self.home = home
        self.makeHealth = makeHealth
        self.makeAgentDetail = makeAgentDetail
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

    /// El detalle de un agente (`AgentDetailView`): lo configurado a la vista y editable en su sitio. Se llega con un clic
    /// en su tarjeta o en «Gestionar». Si la instalación no se puede leer, o el agente ya no está, no se hace nada.
    func openAgent(_ id: UUID, section: AgentDetailModel.Section = .general) {
        guard !home.isUnreadable, home.agents.contains(where: { $0.id == id }) else { return }
        agentDetail?.stop()
        let detail = makeAgentDetail(id, section, home, home.language)
        agentDetail = detail
        language = home.language
        screen = .agent
    }

    /// De vuelta al home desde el detalle. Se vuelve a leer la instalación: allí se pudo cambiar algo.
    func closeAgent() {
        agentDetail?.stop()
        agentDetail = nil
        home.reload()
        language = home.language
        screen = .home
    }

    /// Se eliminó el agente desde su detalle: no hay detalle al que volver. Si era el último, se abre el wizard corto.
    func agentRemovedFromDetail() {
        agentDetail?.stop()
        agentDetail = nil
        screen = .home
        agentRemoved()
    }

    /// «Gestionar»: las pantallas del wizard con lo que el agente ya tiene, para cambiar qué lee, sus skills y sus
    /// reglas. Al guardar se regenera **su** carpeta (`docs/03` §3b) y se vuelve al home. Si la instalación no se
    /// puede leer, o el agente ya no está en ella, no se hace nada.
    func manageAgent(_ id: UUID) {
        guard let installation = home.loadInstallation(), installation.agent(id: id) != nil else { return }
        wizard.stopWorking()
        agentDetail?.stop()
        let fresh = makeEditWizard(installation, id)
        // Si al guardar cambian sus herramientas, se anota: una conversación abierta desde antes no las ve, y el
        // home reinicia Claude al abrir el agente (`AgentOpenPolicy.RestartReason.toolsChanged`).
        let toolsBefore = Set(home.agents.first { $0.id == id }?.tools ?? [])
        fresh.onSaved = { [weak self] in
            guard let self else { return }
            finishWizard()
            let toolsAfter = Set(home.agents.first { $0.id == id }?.tools ?? [])
            if toolsAfter != toolsBefore { home.noteToolsChanged(id) }
        }
        wizard = fresh
        observe(fresh)
        language = fresh.language
        screen = .wizard
    }

    /// «Salud»: qué conexiones están vivas y cómo va WhatsApp. Solo se entra desde el home, con la instalación legible.
    func openHealth() {
        guard screen == .home, !home.isUnreadable else { return }
        let model = makeHealth(home.language)
        model.enableSendingActivation(installer: home.installer) { [home] agents in
            agents.forEach { home.noteToolsChanged($0) }
        }
        health = model
        screen = .health
    }

    /// De vuelta al home desde la salud. Se vuelve a leer la instalación: allí se pudo regenerar o quitar algo.
    func closeHealth() {
        health?.stop()
        health = nil
        home.reload()
        screen = .home
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
