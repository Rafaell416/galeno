import Foundation
import XCTest

@testable import GalenoCore

/// Una sesión falsa: nada de esto habla con Slack de verdad. Guarda la
/// última petición para que las pruebas verifiquen qué se envió.
private actor FakeSlackAPISession: SlackAPISession {
    enum Result {
        case json(status: Int, body: String)
        case failure(any Error)
    }

    private var result: Result
    private(set) var lastRequest: URLRequest?

    init(_ result: Result) {
        self.result = result
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        switch result {
        case let .json(status, body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        case let .failure(error):
            throw error
        }
    }
}

final class SlackAppProvisionerTests: XCTestCase {

    // MARK: - createApp

    func testCreateAppParsesCredentialsFromASuccessfulResponse() async throws {
        let session = FakeSlackAPISession(
            .json(
                status: 200,
                body: """
                    {
                      "ok": true,
                      "app_id": "A012ABCD0A0",
                      "credentials": {
                        "client_id": "1234567890123.1234567890123",
                        "client_secret": "abcdef0123456789abcdef0123456789",
                        "verification_token": "verificacion-de-prueba",
                        "signing_secret": "firma-de-prueba"
                      },
                      "oauth_authorize_url": "https://slack.com/oauth/v2/authorize?client_id=..."
                    }
                    """
            ))

        let credentials = try await SlackAppProvisioner.createApp(
            manifestJSON: "{}", configurationToken: "xoxe.xoxp-prueba", session: session)

        XCTAssertEqual(credentials.appID, "A012ABCD0A0")
        XCTAssertEqual(credentials.clientID, "1234567890123.1234567890123")
        XCTAssertEqual(credentials.clientSecret, "abcdef0123456789abcdef0123456789")
        XCTAssertEqual(credentials.verificationToken, "verificacion-de-prueba")
        XCTAssertEqual(credentials.signingSecret, "firma-de-prueba")
    }

    func testCreateAppSendsTheManifestAsAJSONEncodedString() async throws {
        let session = FakeSlackAPISession(
            .json(status: 200, body: "{\"ok\": true, \"app_id\": \"A1\", \"credentials\": {}}"))
        let manifest = try SlackManifestRenderer.render(agentName: "Hipócrates").manifestJSON

        // No nos importa si esta llamada falla al decodificar (el cuerpo de
        // arriba es deliberadamente incompleto): solo verificamos qué se envió.
        _ = try? await SlackAppProvisioner.createApp(
            manifestJSON: manifest, configurationToken: "xoxe.xoxp-prueba", session: session)

        let sent = await session.lastRequest
        XCTAssertEqual(sent?.url, URL(string: "https://slack.com/api/apps.manifest.create"))
        XCTAssertEqual(sent?.httpMethod, "POST")
        XCTAssertEqual(
            sent?.value(forHTTPHeaderField: "Authorization"), "Bearer xoxe.xoxp-prueba")

        let body = try XCTUnwrap(sent?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        // El manifiesto es un string JSON dentro del campo, no un objeto
        // anidado: así lo documenta apps.manifest.create.
        XCTAssertEqual(object["manifest"] as? String, manifest)
    }

    func testCreateAppReportsAnInvalidManifest() async throws {
        let session = FakeSlackAPISession(
            .json(
                status: 200,
                body: """
                    {
                      "ok": false,
                      "error": "invalid_manifest",
                      "errors": [
                        { "message": "display_information.name es requerido", "pointer": "#/display_information/name" }
                      ]
                    }
                    """
            ))

        do {
            _ = try await SlackAppProvisioner.createApp(
                manifestJSON: "{}", configurationToken: "token", session: session)
            XCTFail("debió lanzar")
        } catch SlackAppProvisioner.ProvisioningError.invalidManifest(let messages) {
            XCTAssertEqual(messages, ["display_information.name es requerido"])
        }
    }

    func testCreateAppReportsAGenericSlackRejection() async throws {
        let session = FakeSlackAPISession(
            .json(status: 200, body: "{\"ok\": false, \"error\": \"invalid_auth\"}"))

        do {
            _ = try await SlackAppProvisioner.createApp(
                manifestJSON: "{}", configurationToken: "token-vencido", session: session)
            XCTFail("debió lanzar")
        } catch SlackAppProvisioner.ProvisioningError.slackRejected(let error) {
            XCTAssertEqual(error, "invalid_auth")
        }
    }

    func testCreateAppReportsATransportFailure() async throws {
        struct Boom: Error {}
        let session = FakeSlackAPISession(.failure(Boom()))

        do {
            _ = try await SlackAppProvisioner.createApp(
                manifestJSON: "{}", configurationToken: "token", session: session)
            XCTFail("debió lanzar")
        } catch SlackAppProvisioner.ProvisioningError.transport(_) {
            // esperado
        }
    }

    func testCreateAppReportsAnUnexpectedResponseShape() async throws {
        let session = FakeSlackAPISession(.json(status: 200, body: "no soy JSON"))

        do {
            _ = try await SlackAppProvisioner.createApp(
                manifestJSON: "{}", configurationToken: "token", session: session)
            XCTFail("debió lanzar")
        } catch SlackAppProvisioner.ProvisioningError.unexpectedResponse {
            // esperado
        }
    }

    /// `ok: true` sin `credentials` no debería colarse como éxito.
    func testCreateAppRejectsASuccessWithoutCredentials() async throws {
        let session = FakeSlackAPISession(
            .json(status: 200, body: "{\"ok\": true, \"app_id\": \"A1\"}"))

        do {
            _ = try await SlackAppProvisioner.createApp(
                manifestJSON: "{}", configurationToken: "token", session: session)
            XCTFail("debió lanzar")
        } catch SlackAppProvisioner.ProvisioningError.unexpectedResponse {
            // esperado
        }
    }

    // MARK: - rotate

    func testRotateParsesTheNewTokenPair() async throws {
        let session = FakeSlackAPISession(
            .json(
                status: 200,
                body: """
                    {
                      "ok": true,
                      "token": "xoxe.xoxp-nuevo",
                      "refresh_token": "xoxe-nuevo",
                      "team_id": "T1",
                      "user_id": "U1",
                      "iat": 1,
                      "exp": 2
                    }
                    """
            ))

        let token = try await SlackAppProvisioner.rotate(
            refreshToken: "xoxe-viejo", session: session)

        XCTAssertEqual(token.accessToken, "xoxe.xoxp-nuevo")
        XCTAssertEqual(token.refreshToken, "xoxe-nuevo")
    }

    /// El refresh_token es la credencial de esta llamada: no lleva Authorization.
    func testRotateDoesNotSendAnAuthorizationHeader() async throws {
        let session = FakeSlackAPISession(
            .json(status: 200, body: "{\"ok\": true, \"token\": \"a\", \"refresh_token\": \"b\"}"))

        _ = try await SlackAppProvisioner.rotate(refreshToken: "xoxe-viejo", session: session)

        let sent = await session.lastRequest
        XCTAssertNil(sent?.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(sent?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["refresh_token"] as? String, "xoxe-viejo")
    }

    func testRotateReportsARejectedRefreshToken() async throws {
        let session = FakeSlackAPISession(
            .json(status: 200, body: "{\"ok\": false, \"error\": \"invalid_refresh_token\"}"))

        do {
            _ = try await SlackAppProvisioner.rotate(refreshToken: "expirado", session: session)
            XCTFail("debió lanzar")
        } catch SlackAppProvisioner.ProvisioningError.slackRejected(let error) {
            XCTAssertEqual(error, "invalid_refresh_token")
        }
    }
}
