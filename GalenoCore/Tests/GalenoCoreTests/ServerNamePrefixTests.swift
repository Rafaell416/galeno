import Foundation
import XCTest

@testable import GalenoCore

/// Cuando el nombre normal (`slack`) ya lo usa otro servidor del usuario en
/// Claude Code, Galeno registra el suyo como `galeno-slack`. Todo lo generado
/// tiene que usar ese mismo nombre: si no, la regla `ask` de Slack apuntaría a
/// un servidor que no existe y el de verdad quedaría sin aprobación.
final class ServerNamePrefixTests: XCTestCase {
    private func config(prefix: String?) -> AgentConfig {
        var value = AgentConfig(
            agentName: "Hera",
            language: .spanish,
            connections: [
                ToolConnection(
                    tool: .slack, status: .connected, sources: .everything,
                    oauthClientID: "1234567890123.1234567890123", serverNamePrefix: prefix),
                ToolConnection(tool: .notion, status: .connected, sources: .everything),
            ])
        value.agentName = "Hera"
        return value
    }

    func testTheCatalogAppliesThePrefixToEveryServerOfTheConnection() {
        let connection = ToolConnection(
            tool: .notion, status: .connected, serverNamePrefix: MCPServerCatalog.alternateNamePrefix)
        let names = MCPServerCatalog.definitions(for: connection, whatsAppBridgePath: "").map(\.serverName)
        XCTAssertEqual(names, ["galeno-notion"])
    }

    /// Un conector de la cuenta de Claude no se registra: su nombre lo pone Claude y no lleva prefijo.
    func testAClaudeAccountConnectorNeverTakesThePrefix() {
        let connection = ToolConnection(
            tool: .googleWorkspace, status: .connected, serverNamePrefix: MCPServerCatalog.alternateNamePrefix)
        let names = MCPServerCatalog.definitions(for: connection, whatsAppBridgePath: "").map(\.serverName)
        XCTAssertEqual(names, ["claude_ai_Google_Drive", "claude_ai_Google_Docs", "claude_ai_Google_Sheets"])
    }

    func testWithoutAPrefixTheNamesAreTheCatalogOnes() {
        let connection = ToolConnection(tool: .slack, status: .connected)
        XCTAssertEqual(
            MCPServerCatalog.definitions(for: connection, whatsAppBridgePath: "").map(\.serverName),
            ["slack"])
    }

    func testMCPJSONUsesTheAlternateName() throws {
        let json = try MCPRenderer.render(config(prefix: "galeno-"), whatsAppBridgePath: "").json
        XCTAssertTrue(json.contains("\"galeno-slack\""))
        XCTAssertFalse(json.contains("\"slack\""))
        XCTAssertTrue(json.contains("\"notion\""), "las demás conservan su nombre")
    }

    func testPermissionRulesAndTheApprovalHookFollowTheAlternateName() throws {
        let settings = try SettingsRenderer.render(config(prefix: "galeno-"))
        XCTAssertTrue(settings.contains("mcp__galeno-slack__slack_send_message"), "la regla ask")
        XCTAssertTrue(settings.contains("mcp__galeno-slack__slack_read_channel"), "la regla allow de las lecturas")
        XCTAssertTrue(settings.contains("^mcp__galeno-slack__(?!"), "el matcher del hook")
        XCTAssertFalse(settings.contains("mcp__slack__"), "ninguna regla apunta al nombre que no existe")
    }

    func testSubagentsNeverGetTheAlternateSlackServerEither() {
        let granted = SubagentsRenderer.grantedServers(in: config(prefix: "galeno-"))
        XCTAssertEqual(granted, ["notion"])
    }

    func testThePrefixTravelsFromTheInstallationToTheAgentConfig() throws {
        var installation = GalenoInstallation(
            language: .spanish,
            connections: [
                SharedConnection(
                    tool: .slack, status: .connected,
                    oauthClientID: "1234567890123.1234567890123", serverNamePrefix: "galeno-")
            ])
        let sandbox = FileManager.default.temporaryDirectory
            .appending(path: "galeno-prefix/\(UUID().uuidString)", directoryHint: .isDirectory)
        let record = installation.addAgent(
            installation.startingPoint(agentName: "Hera"), agentsRoot: sandbox)
        XCTAssertEqual(
            try XCTUnwrap(installation.resolvedConfig(for: record.id)).connection(for: .slack)?.serverNamePrefix,
            "galeno-")
    }

    /// Las instalaciones guardadas antes de que existiera el campo siguen leyéndose.
    func testOlderFilesWithoutTheFieldStillDecode() throws {
        let encoded = try JSONEncoder().encode(ToolConnection(tool: .slack, status: .connected))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "serverNamePrefix")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(ToolConnection.self, from: old).serverNamePrefix)
    }
}
