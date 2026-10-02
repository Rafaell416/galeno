import Foundation

/// Escribe `.mcp.json`: una entrada por herramienta conectada que tenga servidor
/// propio.
///
/// Ningún token aparece como valor. Los servidores con OAuth no llevan nada de
/// autenticación —Claude Code la gestiona— y los que usan cabecera reciben una
/// referencia `${VARIABLE}`, porque ``MCPAuthentication`` solo guarda el nombre
/// de la variable.
enum MCPRenderer {
    /// Una entrada de `mcpServers`. Las propiedades opcionales en `nil` no se
    /// escriben.
    private struct Server: Encodable {
        var type: String
        var command: String?
        var args: [String]?
        var url: String?
        var headers: [String: String]?
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

        for tool in config.connectedTools {
            guard
                let definition = MCPServerCatalog.definition(
                    for: tool, whatsAppBridgePath: whatsAppBridgePath)
            else {
                // Google Meet no tiene servidor propio: se lee por Drive.
                continue
            }

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

            switch definition.authentication {
            case .oauth:
                break
            case let .bearerToken(variable):
                // Una referencia, nunca el valor: Claude Code expande ${VAR}.
                server.headers = ["Authorization": "Bearer ${\(variable)}"]
            }

            servers[definition.serverName] = server
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(File(mcpServers: servers))
        let json = String(decoding: data, as: UTF8.self)

        return Output(json: json + "\n", warnings: warnings)
    }
}
