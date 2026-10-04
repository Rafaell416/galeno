import Combine
import Foundation
import GalenoCore

/// Las listas de la pantalla 6 ("Elige qué leer"): para cada herramienta conectada, lo que el
/// usuario puede elegir leer. Se piden en segundo plano al entrar a la pantalla, de a pocas a la
/// vez (cada una de Claude Code gasta de la cuota del usuario), y **nada bloquea**: una que falla
/// o tarda se puede reintentar o dejar que el agente lo lea todo.
///
/// La selección no vive aquí sino en `WizardState.connections[].sources`: es parte de la config.
@MainActor
final class SourcesFlow: ObservableObject {
    enum Load: Equatable {
        case loading
        case loaded([Source], isPartial: Bool)
        case failed(String)
    }

    /// Las herramientas de la pantalla, en el orden de las conexiones.
    let tools: [Tool]
    /// Las que tienen una lista que elegir. El resto (reuniones transcritas) lee todo.
    var listedTools: [Tool] { tools.filter { !$0.selectableSourceKinds.isEmpty } }

    @Published private(set) var loads: [Tool: Load] = [:]

    private let connections: [ToolConnection]
    private let lister: any SourceListing
    /// Cuántas consultas corren a la vez.
    private let maxConcurrent: Int
    private var tasks: [Tool: Task<Void, Never>] = [:]
    private var pending: [Tool] = []
    private var running = 0

    init(connections: [ToolConnection], lister: any SourceListing, maxConcurrent: Int = 3) {
        let connected = connections.filter { $0.status == .connected }
        self.connections = connected
        self.tools = connected.map(\.tool)
        self.lister = lister
        self.maxConcurrent = maxConcurrent
    }

    /// Google Meet se lee con Drive: comparte la lista de Google Workspace.
    private func source(of tool: Tool) -> Tool { tool == .googleMeet ? .googleWorkspace : tool }

    /// La carga de una herramienta (Meet, la de Workspace).
    func load(of tool: Tool) -> Load? { loads[source(of: tool)] }

    func sources(of tool: Tool) -> [Source] {
        if case .loaded(let list, _)? = load(of: tool) { return list }
        return []
    }

    /// Pide todas las listas que falten. Se puede llamar varias veces: lo ya cargado o en
    /// camino no se repite.
    func start() {
        // WhatsApp primero: es local y casi instantáneo.
        let order = listedTools.map(source(of:)).reduce(into: [Tool]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted { ($0 == .whatsapp ? 0 : 1) < ($1 == .whatsapp ? 0 : 1) }
        for tool in order where loads[tool] == nil {
            loads[tool] = .loading
            pending.append(tool)
        }
        pump()
    }

    func retry(_ tool: Tool) {
        let key = source(of: tool)
        guard case .failed? = loads[key] else { return }
        loads[key] = .loading
        pending.append(key)
        pump()
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        pending = []
        running = 0
        for (tool, load) in loads where load == .loading { loads[tool] = nil }
    }

    // MARK: Interno

    private func pump() {
        while running < maxConcurrent, !pending.isEmpty {
            let tool = pending.removeFirst()
            guard let connection = connections.first(where: { $0.tool == tool }) else {
                loads[tool] = .loaded([], isPartial: false)
                continue
            }
            running += 1
            tasks[tool] = Task { [weak self, lister] in
                let result = await lister.list(connection)
                guard let self, !Task.isCancelled else { return }
                self.finish(tool, result)
            }
        }
    }

    private func finish(_ tool: Tool, _ result: SourceListResult) {
        running = max(0, running - 1)
        tasks[tool] = nil
        switch result {
        case .loaded(let list, let isPartial): loads[tool] = .loaded(list, isPartial: isPartial)
        case .failed(let reason): loads[tool] = .failed(reason)
        }
        pump()
    }
}
