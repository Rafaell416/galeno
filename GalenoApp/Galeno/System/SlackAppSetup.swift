import Foundation
import GalenoCore

/// Por qué falló crear la app de Slack, ya clasificado para decirle al usuario qué hacer.
nonisolated enum SlackSetupError: Error, Equatable, Sendable {
    /// Slack no aceptó el token: venció (duran 12 h), está mal copiado o es el equivocado.
    case tokenRejected(String)
    /// Slack no dejó crear la app: casi siempre falta la aprobación de un administrador.
    case notAllowed(String)
    case invalidManifest([String])
    case unreachable(String)
    case unexpected
}

/// Crea la app de Slack del cliente (`docs/03` §4e). Las pruebas lo reemplazan por uno falso.
///
/// El token de configuración es un `OAuthSecret` y no se guarda en ninguna parte: se usa
/// para esto y se descarta. Hay una app por workspace, compartida por todos los agentes.
nonisolated protocol SlackAppSetting: Sendable {
    /// Comprueba el token y la configuración **sin crear nada**.
    func validate(token: OAuthSecret, agentName: String) async throws
    /// Crea la app y devuelve cómo registrarla en Claude Code: su `client_id`, el puerto del
    /// callback y el `client_secret`, que no se guarda en ninguna parte.
    func createApp(token: OAuthSecret, agentName: String) async throws -> OAuthClientRegistration
}

nonisolated struct SlackAppSetupService: SlackAppSetting {
    var session: any SlackAPISession = URLSessionSlackAPISession()

    func validate(token: OAuthSecret, agentName: String) async throws {
        let manifest = try manifestJSON(agentName)
        do {
            try await token.withValueAsync { value in
                try await SlackAppProvisioner.validate(
                    manifestJSON: manifest, configurationToken: value, session: session)
            }
        } catch {
            throw Self.classify(error)
        }
    }

    func createApp(token: OAuthSecret, agentName: String) async throws -> OAuthClientRegistration {
        let manifest = try manifestJSON(agentName)
        let credentials: SlackAppProvisioner.Credentials
        do {
            credentials = try await token.withValueAsync { value in
                try await SlackAppProvisioner.createApp(
                    manifestJSON: manifest, configurationToken: value, session: session)
            }
        } catch {
            throw Self.classify(error)
        }
        // Solo se conserva lo necesario para registrar el servidor. El resto de lo que devuelve
        // Slack (`signingSecret`, `verificationToken`) no se usa y se suelta aquí.
        return OAuthClientRegistration(
            clientID: credentials.clientID,
            callbackPort: SlackOAuth.callbackPort,
            secret: OAuthSecret(credentials.clientSecret),
            appID: credentials.appID)
    }

    private func manifestJSON(_ agentName: String) throws -> String {
        do {
            return try SlackManifestRenderer.render(agentName: agentName).manifestJSON
        } catch {
            throw SlackSetupError.unexpected
        }
    }

    /// Códigos con los que Slack dice "este token no sirve".
    private static let tokenProblems: Set<String> = [
        "invalid_auth", "not_authed", "token_expired", "token_revoked", "account_inactive",
        "invalid_token", "not_allowed_token_type", "bad_token",
    ]

    static func classify(_ error: any Error) -> SlackSetupError {
        if let error = error as? SlackSetupError { return error }
        guard let error = error as? SlackAppProvisioner.ProvisioningError else { return .unexpected }
        switch error {
        case .invalidManifest(let messages): return .invalidManifest(messages)
        case .slackRejected(let code):
            return tokenProblems.contains(code) ? .tokenRejected(code) : .notAllowed(code)
        case .transport(let description): return .unreachable(description)
        case .unexpectedResponse: return .unexpected
        }
    }
}
