import Foundation

/// Crea la app de Slack del cliente **por API**, sin que nadie copie nada de
/// una pantalla.
///
/// `apps.manifest.create` de Slack recibe el manifiesto y devuelve el
/// `client_id`/`client_secret` directamente en la respuesta (verificado
/// contra la referencia oficial del método). Eso evita por completo lo que
/// `SlackManifestRenderer` todavía dejaba en manos del usuario: ya no hace
/// falta abrir el enlace de instalación ni copiar nada de la pantalla de
/// "Información básica" de Slack.
///
/// **Lo único que Slack no deja automatizar:** la primera vez, alguien tiene
/// que generar a mano un "token de configuración de apps" en
/// `api.slack.com/apps` → "Your App Configuration Tokens" → "Generate
/// Token". La propia documentación de Slack lo dice explícitamente: no existe
/// una forma programática de arrancar ese primer token. Es un paso único por
/// workspace —no por conexión, no por app—, y de ahí en adelante
/// ``rotate(refreshToken:session:)`` lo renueva solo, sin que nadie vuelva a
/// tocar nada.
///
/// **El `client_secret` pasa por aquí, en memoria, una sola vez.** Esto
/// cambia algo respecto al resto del motor: `GalenoCore` nunca lo escribe a
/// disco ni lo registra, pero sí lo recibe de Slack de vuelta. Quien llame a
/// ``createApp(manifestJSON:configurationToken:session:)`` tiene la
/// responsabilidad de entregarlo de inmediato a un almacenamiento seguro
/// (`claude mcp add --client-secret`, que Claude Code guarda en el keychain
/// del sistema) y no retenerlo. Nada de esto sale de la máquina del
/// usuario: sigue siendo "los secretos nunca tocan infraestructura propia",
/// solo que ahora Galeno los ve de paso, en vez de no verlos nunca.
public enum SlackAppProvisioner {

    // MARK: - Tipos públicos

    /// Lo que devuelve Slack al crear la app.
    public struct Credentials: Hashable, Sendable {
        public var appID: String
        public var clientID: String
        /// Ver la nota de confianza en la documentación del tipo: vive solo
        /// en memoria, de paso.
        public var clientSecret: String
        public var verificationToken: String
        public var signingSecret: String
    }

    /// El par de tokens de configuración de Slack.
    public struct ConfigurationToken: Hashable, Sendable {
        /// `xoxe.xoxp-...`. Expira a las 12 horas.
        public var accessToken: String
        /// `xoxe-...`. Sirve para renovar el de arriba indefinidamente.
        public var refreshToken: String
    }

    public enum ProvisioningError: Error, Equatable, CustomStringConvertible {
        /// Slack rechazó el manifiesto. `pointers` ubica qué campo falló.
        case invalidManifest(messages: [String])
        /// Slack respondió `ok: false` con otro motivo (token vencido,
        /// token sin permiso, etc.).
        case slackRejected(error: String)
        /// La respuesta no tuvo la forma esperada.
        case unexpectedResponse
        /// Fallo de red o de transporte, con su descripción (no guarda el
        /// `Error` original para poder seguir siendo `Equatable`, útil en pruebas).
        case transport(description: String)

        public var description: String {
            switch self {
            case let .invalidManifest(messages):
                "Slack rechazó el manifiesto: \(messages.joined(separator: "; "))"
            case let .slackRejected(error):
                "Slack respondió con un error: \(error)"
            case .unexpectedResponse:
                "La respuesta de Slack no tuvo la forma esperada."
            case let .transport(description):
                "No se pudo hablar con Slack: \(description)"
            }
        }
    }

    // MARK: - Las dos llamadas

    /// Crea la app del cliente en Slack y devuelve sus credenciales.
    public static func createApp(
        manifestJSON: String,
        configurationToken: String,
        session: SlackAPISession = URLSessionSlackAPISession()
    ) async throws -> Credentials {
        var request = URLRequest(url: Endpoint.createApp)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configurationToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // El manifiesto va como string JSON dentro del cuerpo, no como
        // objeto anidado: así lo documenta apps.manifest.create.
        request.httpBody = try JSONEncoder().encode(["manifest": manifestJSON])

        let data = try await send(request, session: session)
        let response = try decode(CreateAppResponse.self, from: data)

        guard response.ok else {
            if let messages = response.errors?.map(\.message), !messages.isEmpty {
                throw ProvisioningError.invalidManifest(messages: messages)
            }
            throw ProvisioningError.slackRejected(error: response.error ?? "desconocido")
        }
        guard let appID = response.appId, let credentials = response.credentials else {
            throw ProvisioningError.unexpectedResponse
        }

        return Credentials(
            appID: appID,
            clientID: credentials.clientId,
            clientSecret: credentials.clientSecret,
            verificationToken: credentials.verificationToken,
            signingSecret: credentials.signingSecret
        )
    }

    /// Renueva el token de configuración usando el `refresh_token`. Se llama
    /// cuando el `accessToken` —de 12 horas— venció; el `refreshToken` en sí
    /// no se consume y sigue sirviendo para la próxima vez.
    public static func rotate(
        refreshToken: String,
        session: SlackAPISession = URLSessionSlackAPISession()
    ) async throws -> ConfigurationToken {
        var request = URLRequest(url: Endpoint.rotateToken)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // Esta llamada no lleva Authorization: el propio refresh_token es la
        // credencial (confirmado contra la referencia de tooling.tokens.rotate).
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

        let data = try await send(request, session: session)
        let response = try decode(RotateResponse.self, from: data)

        guard response.ok else {
            throw ProvisioningError.slackRejected(error: response.error ?? "desconocido")
        }
        guard let token = response.token, let newRefreshToken = response.refreshToken else {
            throw ProvisioningError.unexpectedResponse
        }

        return ConfigurationToken(accessToken: token, refreshToken: newRefreshToken)
    }

    // MARK: - Privado

    private enum Endpoint {
        static let createApp = URL(string: "https://slack.com/api/apps.manifest.create")!
        static let rotateToken = URL(string: "https://slack.com/api/tooling.tokens.rotate")!
    }

    private static func send(_ request: URLRequest, session: SlackAPISession) async throws -> Data
    {
        do {
            let (data, _) = try await session.send(request)
            return data
        } catch let error as ProvisioningError {
            throw error
        } catch {
            throw ProvisioningError.transport(description: error.localizedDescription)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ProvisioningError.unexpectedResponse
        }
    }

    // Las formas exactas de la respuesta, verificadas contra la referencia
    // oficial de cada método. `keyDecodingStrategy = .convertFromSnakeCase`
    // traduce `app_id` → `appId`, `client_id` → `clientId`, etc.
    private struct CreateAppResponse: Decodable {
        var ok: Bool
        var appId: String?
        var credentials: ResponseCredentials?
        var error: String?
        var errors: [ManifestFieldError]?

        struct ResponseCredentials: Decodable {
            var clientId: String
            var clientSecret: String
            var verificationToken: String
            var signingSecret: String
        }
    }

    private struct ManifestFieldError: Decodable {
        var message: String
        var pointer: String?
    }

    private struct RotateResponse: Decodable {
        var ok: Bool
        var token: String?
        var refreshToken: String?
        var error: String?
    }
}

/// Lo mínimo para que `SlackAppProvisioner` pueda hacer una petición HTTP sin
/// atarse a `URLSession`, para que las pruebas no hablen con Slack de verdad.
public protocol SlackAPISession: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

/// La implementación real, con `URLSession.shared`.
public struct URLSessionSlackAPISession: SlackAPISession {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}
