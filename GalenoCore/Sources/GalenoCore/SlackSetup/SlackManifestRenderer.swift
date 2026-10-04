import Foundation

/// La constante que conecta el manifiesto de Slack con `.mcp.json`.
///
/// El manifiesto declara a qué URL puede volver Slack tras la autorización
/// (`redirect_urls`); `.mcp.json` le dice a Claude Code en qué puerto local
/// esperar esa vuelta (`oauth.callbackPort`). Si no coinciden, la
/// autorización falla — por eso es una sola constante compartida entre
/// `SlackManifestRenderer` y `MCPRenderer`, nunca dos números escritos a mano.
public enum SlackOAuth {
    public static let callbackPort = 51820
    public static var redirectURL: String { "http://localhost:\(callbackPort)/callback" }
}

/// Construye el manifiesto de la app de Slack que el cliente crea para su
/// propio workspace, y el enlace que la crea de un clic.
///
/// Esta app **es del cliente, nunca de Galeno**: cada empresa registra la
/// suya. El servidor MCP de Slack solo soporta el flujo de **token de
/// usuario** (confirmado contra docs.slack.dev: sus endpoints de
/// autorización son específicamente `oauth/v2_user/authorize`), así que todo
/// lo que el agente haga en Slack aparece con el nombre y la foto de quien
/// aprobó la conexión — no existe una identidad de bot separada dentro de
/// esta integración. `agentName` solo nombra la app tal como la ve el admin
/// de Slack al aprobarla; no es una marca que los compañeros de equipo vean.
///
/// No escribe nada a disco ni depende de `ConfigGenerator`: se usa durante el
/// paso de conexión del wizard, antes de que exista un `AgentConfig`
/// completo (el `client_id` que resulte de esto es lo que luego se guarda en
/// `ToolConnection.oauthClientID`).
public enum SlackManifestRenderer {
    /// Los scopes que v0.0.1 necesita, todos de **token de usuario**
    /// (verificados contra la tabla de docs.slack.dev/ai/slack-mcp-server/).
    /// Deliberadamente no se piden scopes de archivos, reacciones, canvases,
    /// listas ni mensajes directos: v0.0.1 no usa esas capacidades, y pedir
    /// de más viola el mínimo privilegio. Revisar cuando el wizard real
    /// confirme qué herramientas MCP invoca de verdad.
    public static let requiredScopes: [String] = [
        "channels:read", "groups:read",
        "channels:history", "groups:history",
        "search:read.public", "search:read.private",
        "chat:write",
    ]

    public struct Result: Hashable, Sendable {
        /// El manifiesto, como JSON de texto.
        public var manifestJSON: String
        /// `api.slack.com/apps?new_app=1&manifest_json=<codificado>`. Abrirlo
        /// en el navegador del usuario (ya logueado en su Slack) lleva
        /// directo a la pantalla de "revisar y crear", sin que nadie llene
        /// un formulario a mano.
        public var installURL: URL
    }

    // Los tipos Encodable son privados: son detalle de implementación del
    // formato del manifiesto, no algo que el llamador deba conocer.
    private struct DisplayInformation: Encodable {
        var name: String
        var description: String
    }

    private struct OAuthScopes: Encodable {
        var user: [String]
    }

    private struct OAuthConfig: Encodable {
        var redirect_urls: [String]
        var scopes: OAuthScopes
    }

    /// `is_mcp_enabled` es el interruptor «Slack Model Context Protocol (MCP) Server» de la página
    /// *Agents & AI Apps* de la app (documentado en la referencia del manifiesto). Sin él, Slack
    /// responde «App is not enabled for Slack MCP server access» aunque la autorización salga bien.
    private struct Settings: Encodable {
        var is_mcp_enabled: Bool
    }

    private struct Manifest: Encodable {
        var display_information: DisplayInformation
        var oauth_config: OAuthConfig
        var settings: Settings
    }

    /// `agentName` es el nombre del agente del usuario ("Hipócrates"); se usa
    /// tal cual como nombre de la app de Slack, salvo que ya incluya "Galeno".
    public static func render(agentName: String) throws -> Result {
        let appName = agentName.localizedCaseInsensitiveContains("galeno")
            ? agentName
            : "\(agentName) (Galeno)"

        let manifest = Manifest(
            display_information: DisplayInformation(
                name: String(appName.prefix(35)),  // límite de Slack para el nombre
                description: "Conecta \(agentName), tu agente de Galeno, con tu Slack."
            ),
            oauth_config: OAuthConfig(
                redirect_urls: [SlackOAuth.redirectURL],
                scopes: OAuthScopes(user: requiredScopes)
            ),
            settings: Settings(is_mcp_enabled: true)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        let json = String(decoding: data, as: UTF8.self)

        var components = URLComponents(string: "https://api.slack.com/apps")!
        components.queryItems = [
            URLQueryItem(name: "new_app", value: "1"),
            URLQueryItem(name: "manifest_json", value: json),
        ]
        // URLComponents no codifica "+" dentro de queryItems; un manifiesto
        // JSON no lleva "+", así que no hace falta nada adicional aquí.
        let installURL = components.url!

        return Result(manifestJSON: json, installURL: installURL)
    }
}
