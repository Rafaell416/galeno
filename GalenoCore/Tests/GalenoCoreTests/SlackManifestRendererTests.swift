import Foundation
import XCTest

@testable import GalenoCore

final class SlackManifestRendererTests: XCTestCase {
    func testManifestHasTheExpectedShape() throws {
        let result = try SlackManifestRenderer.render(agentName: "Hipócrates")
        let data = Data(result.manifestJSON.utf8)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let display = try XCTUnwrap(object["display_information"] as? [String: Any])
        XCTAssertEqual(display["name"] as? String, "Hipócrates (Galeno)")
        XCTAssertFalse((display["description"] as? String ?? "").isEmpty)

        let oauth = try XCTUnwrap(object["oauth_config"] as? [String: Any])
        XCTAssertEqual(oauth["redirect_urls"] as? [String], [SlackOAuth.redirectURL])

        let scopes = try XCTUnwrap(oauth["scopes"] as? [String: Any])
        XCTAssertEqual(scopes["user"] as? [String], SlackManifestRenderer.requiredScopes)
        // El servidor MCP de Slack solo soporta token de usuario: no debe
        // existir una entrada de scopes de bot.
        XCTAssertNil(scopes["bot"])
    }

    /// Sin `is_mcp_enabled`, Slack contesta «App is not enabled for Slack MCP server access» aunque
    /// el usuario autorice la app: se comprobó con una app real.
    func testManifestTurnsOnTheSlackMCPServerForTheApp() throws {
        let result = try SlackManifestRenderer.render(agentName: "Hipócrates")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.manifestJSON.utf8)) as? [String: Any])
        let settings = try XCTUnwrap(object["settings"] as? [String: Any])
        XCTAssertEqual(settings["is_mcp_enabled"] as? Bool, true)
    }

    /// No le pega el nombre "Galeno" dos veces si el usuario ya lo incluyó.
    func testDoesNotDoubleUpGalenoInTheName() throws {
        let result = try SlackManifestRenderer.render(agentName: "Galeno de Acme")
        let data = Data(result.manifestJSON.utf8)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let display = try XCTUnwrap(object["display_information"] as? [String: Any])

        XCTAssertEqual(display["name"] as? String, "Galeno de Acme")
    }

    /// El límite de Slack para el nombre de la app es 35 caracteres.
    func testNameIsTruncatedToSlacksLimit() throws {
        let longName = String(repeating: "Hipócrates el Grande ", count: 5)
        let result = try SlackManifestRenderer.render(agentName: longName)
        let data = Data(result.manifestJSON.utf8)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let display = try XCTUnwrap(object["display_information"] as? [String: Any])
        let name = try XCTUnwrap(display["name"] as? String)

        XCTAssertLessThanOrEqual(name.count, 35)
    }

    /// El servidor de `.mcp.json` y el manifiesto tienen que ponerse de
    /// acuerdo en el puerto de redirección, o la autorización falla.
    func testRedirectURLUsesTheSharedCallbackPort() {
        XCTAssertEqual(SlackOAuth.redirectURL, "http://localhost:51820/callback")
    }

    func testInstallURLRoundTripsTheManifest() throws {
        let result = try SlackManifestRenderer.render(agentName: "Hipócrates")

        let components = try XCTUnwrap(
            URLComponents(url: result.installURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "api.slack.com")
        XCTAssertEqual(components.path, "/apps")

        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.first { $0.name == "new_app" }?.value, "1")

        let embeddedJSON = try XCTUnwrap(items.first { $0.name == "manifest_json" }?.value)
        XCTAssertEqual(embeddedJSON, result.manifestJSON)
    }

    func testOnlyUserTokenScopesAreRequested() {
        // Confirmado contra docs.slack.dev: el MCP de Slack usa el flujo de
        // token de usuario (oauth/v2_user/authorize). Pedir scopes de bot
        // no tendría efecto y podría confundir a quien lea el manifiesto.
        XCTAssertFalse(SlackManifestRenderer.requiredScopes.isEmpty)
        for scope in SlackManifestRenderer.requiredScopes {
            XCTAssertFalse(scope.isEmpty)
        }
    }
}
