import Foundation

/// Escribe `.mcp.json`: una o más entradas por herramienta conectada que
/// tenga servidor propio (Google Workspace son tres: Drive, Docs y Sheets).
///
/// Ningún secreto aparece como valor. Los servidores con registro dinámico no
/// llevan nada de autenticación —Claude Code la gestiona—; los que usan
/// cabecera reciben una referencia `${VARIABLE}`; y los que exigen la app
/// propia del cliente (Slack, Gmail, Google Workspace) llevan su `client_id`
/// —que no es secreto— pero nunca un `client_secret`.
enum MCPRenderer {
    /// Una entrada de `mcpServers`. Las propiedades opcionales en `nil` no se
    /// escriben.
    private struct Server: Encodable {
        var type: String
        var command: String?
        var args: [String]?
        var url: String?
        var headers: [String: String]?
        var oauth: OAuthConfig?
    }

    private struct OAuthConfig: Encodable {
        var clientId: String
        /// Espacio-separados, como espera Claude Code. `nil` si no hay una
        /// lista verificada todavía (hoy, el caso de Gmail/Google Workspace).
        var scopes: String?
        /// Fijo solo para Slack por ahora: ver ``SlackOAuth``.
        var callbackPort: Int?
    }

    private struct File: Encodable {
        var mcpServers: [String: Server]
    }

    struct Output {
        var json: String
        var warnings: [GenerationWarning]
    }

    static func render(_ config: AgentConfig, whatsAppBridgePath: String) throws -> Output {
        var servers: [String: Server] = [:]
        var warnings: [GenerationWarning] = []

        for connection in config.connections where connection.status == .connected {
            let tool = connection.tool
            let definitions = MCPServerCatalog.definitions(
                for: connection, whatsAppBridgePath: whatsAppBridgePath)
            guard !definitions.isEmpty else {
                // Google Meet no tiene servidor propio: se lee por Drive.
                continue
            }

            // Una sola decisión de autenticación por herramienta, aplicada a
            // todos sus servidores físicos (las tres de Google Workspace
            // comparten el mismo client_id: es la misma app del cliente).
            var toolWideAuthentication: MCPAuthentication?
            if tool.requiresUserProvidedOAuthClient {
                let clientID = connection.oauthClientID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let clientID, !clientID.isEmpty else {
                    throw GenerationError.missingOAuthClient(tool: tool)
                }
                // Scopes verificados solo para Slack por ahora (spec §4b de
                // esta investigación). Para Gmail/Google Workspace no hay
                // todavía una tabla verificada; se omite el campo en vez de
                // inventar uno.
                let scopes = tool == .slack ? SlackManifestRenderer.requiredScopes : []
                toolWideAuthentication = .oauthWithUserProvidedClient(
                    clientID: clientID, scopes: scopes)
            }

            for definition in definitions {
                var server: Server
                switch definition.transport {
                case let .stdio(command, arguments):
                    server = Server(type: "stdio", command: command, args: arguments)
                case let .http(url):
                    server = Server(type: "http", url: url)
                    if !definition.endpointIsVerified {
                        warnings.append(.unverifiedEndpoint(tool: tool, url: url))
                    }
                }

                switch toolWideAuthentication ?? definition.authentication {
                case .oauth:
                    break
                case let .oauthWithUserProvidedClient(clientID, scopes):
                    server.oauth = OAuthConfig(
                        clientId: clientID,
                        scopes: scopes.isEmpty ? nil : scopes.joined(separator: " "),
                        callbackPort: tool == .slack ? SlackOAuth.callbackPort : nil
                    )
                case let .bearerToken(variable):
                    // Una referencia, nunca el valor: Claude Code expande ${VAR}.
                    server.headers = ["Authorization": "Bearer ${\(variable)}"]
                }

                servers[definition.serverName] = server
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(File(mcpServers: servers))
        let json = String(decoding: data, as: UTF8.self)

        return Output(json: json + "\n", warnings: warnings)
    }
}
