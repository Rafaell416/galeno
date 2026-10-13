import Foundation
import GalenoCore

/// Conecta **otra cuenta** de una herramienta que Galeno registra (Notion, Jira, las de reuniones): un servidor más en
/// Claude Code con su propio nombre (`galeno-notion-trabajo`), registrado y autorizado como el de siempre.
///
/// Es el mismo camino que la reconexión de Salud (`status` → `register` → `login` → `status`), sin el asistente:
/// idempotente, así que sirve igual para reconectar una cuenta extra que dejó de responder. **Nunca pisa** un servidor
/// del usuario con ese nombre (`.nameInUse`) ni cierra la sesión de nadie.
///
/// Slack no entra todavía: cada cuenta necesita su propia app de Slack (`Tool.requiresUserProvidedOAuthClient`).
nonisolated struct AccountConnector: Sendable {
    enum Issue: Error, Equatable, Sendable {
        /// El nombre no tiene ninguna letra ni número.
        case invalidName
        /// Ya hay una cuenta de esa herramienta con ese nombre.
        case alreadyExists
        /// La herramienta no admite cuentas extra desde aquí.
        case unsupported
        /// Otro servidor del usuario usa ese nombre: Galeno no lo toca.
        case nameInUse
        case couldNotRegister(String)
        case notAuthorizedInTime
        case loginFailed(String)
        case stillNotConnected
        /// El `claude` de este Mac es demasiado viejo para autorizar.
        case claudeOutdated
    }

    var mcp: any MCPConnecting

    /// Lo más largo que puede ser el nombre que se ve (el identificador sale de él y se acorta aparte).
    static let maxNameLength = 40

    /// ¿Se puede añadir otra cuenta de esta herramienta desde la app? Solo las que Galeno registra con su propio
    /// prefijo y se autorizan con el OAuth del propio servidor.
    static func canAdd(_ tool: Tool) -> Bool {
        guard tool.supportsMultipleAccounts, !tool.requiresUserProvidedOAuthClient else { return false }
        // Galeno registra un servidor hospedado para ella (con su prefijo `galeno-`).
        return MCPServerCatalog.defaultNamePrefix(for: tool) != nil
    }

    /// El nombre que escribió el usuario convertido en la conexión por conectar. `existing`: las cuentas que ya hay
    /// de esa herramienta (en el agente o en la instalación).
    static func prepare(tool: Tool, name: String, existing: [ConnectionID]) -> Result<ToolConnection, Issue> {
        guard canAdd(tool) else { return .failure(.unsupported) }
        let shown = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = AccountID.slug(from: shown) else { return .failure(.invalidName) }
        guard !existing.contains(ConnectionID(tool: tool, account: account)) else { return .failure(.alreadyExists) }
        return .success(
            ToolConnection(
                tool: tool, status: .connected, sources: .everything,
                serverNamePrefix: MCPServerCatalog.ownedNamePrefix, accountID: account, accountName: shown))
    }

    /// Registra y autoriza la cuenta. `nil` = quedó conectada (o ya lo estaba).
    func connect(_ connection: ToolConnection, openAuthorization: AuthorizationOpener? = nil) async -> Issue? {
        guard connection.tool.supportsMultipleAccounts, !connection.tool.requiresUserProvidedOAuthClient,
            let server = Self.server(of: connection)
        else { return .unsupported }

        switch await mcp.status(of: server.name, expectingURL: server.url) {
        case .connected:
            return nil
        case .differentServer:
            return .nameInUse
        case .notRegistered:
            do { try await mcp.register(server: server.name, url: server.url, oauth: nil) } catch {
                if let error = error as? MCPConnectError, case .registerFailed(let detail) = error {
                    return .couldNotRegister(detail)
                }
                return .couldNotRegister("")
            }
        case .needsAuthentication, .failed, .pending:
            break
        }
        if Task.isCancelled { return nil }

        do {
            try await mcp.login(server: server.name, openAuthorization: openAuthorization)
        } catch let error as MCPConnectError {
            if Task.isCancelled || error == .cancelled { return nil }
            switch error {
            case .loginTimedOut: return .notAuthorizedInTime
            case .notConnectedAfterLogin: return .stillNotConnected
            case .claudeOutdated: return .claudeOutdated
            case .loginFailed(let detail): return .loginFailed(detail)
            default: return .loginFailed("")
            }
        } catch {
            return .loginFailed("")
        }
        if Task.isCancelled { return nil }
        let after = await mcp.status(of: server.name, expectingURL: server.url)
        return after == .connected ? nil : .stillNotConnected
    }

    /// El servidor de esa cuenta, con su nombre propio y su dirección.
    static func server(of connection: ToolConnection) -> (name: String, url: String)? {
        for definition in MCPServerCatalog.definitions(for: connection, whatsAppBridgePath: "") {
            if case .http(let url) = definition.transport { return (definition.serverName, url) }
        }
        return nil
    }
}
