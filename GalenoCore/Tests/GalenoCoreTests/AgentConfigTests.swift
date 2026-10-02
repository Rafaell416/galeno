import Foundation
import XCTest

@testable import GalenoCore

final class AgentConfigTests: XCTestCase {
    func testRoundTripPreservesTheWholeConfig() throws {
        let original = AgentConfig.example

        let data = try AgentConfig.jsonEncoder.encode(original)
        let decoded = try AgentConfig.jsonDecoder.decode(AgentConfig.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testRoundTripCoversEveryTool() throws {
        let data = try AgentConfig.jsonEncoder.encode(AgentConfig.example)
        let decoded = try AgentConfig.jsonDecoder.decode(AgentConfig.self, from: data)

        XCTAssertEqual(decoded.connections.map(\.tool), Tool.allCases)
    }

    func testRoundTripCoversEverySourceKind() throws {
        let data = try AgentConfig.jsonEncoder.encode(AgentConfig.example)
        let decoded = try AgentConfig.jsonDecoder.decode(AgentConfig.self, from: data)

        let kinds = Set(decoded.connections.flatMap(\.sources.selected).map(\.kind))
        XCTAssertEqual(kinds, Set(SourceKind.allCases))
    }

    /// Decodifica un JSON escrito a mano. Si alguien renombra una propiedad o
    /// cambia un raw value, esta prueba falla: las configs que los usuarios ya
    /// tienen guardadas en disco dejarían de leerse.
    func testDecodesAStableJSONShape() throws {
        let json = """
            {
              "schemaVersion": 1,
              "agentName": "Hipócrates",
              "language": "es",
              "role": "product-manager",
              "connections": [
                {
                  "tool": "whatsapp",
                  "status": "connected",
                  "sources": {
                    "readsEverything": false,
                    "selected": [
                      { "id": "1203@g.us", "name": "Equipo Cliente A", "kind": "group" }
                    ]
                  }
                },
                {
                  "tool": "google-meet",
                  "status": "skipped",
                  "sources": { "readsEverything": true, "selected": [] }
                }
              ],
              "skills": [
                { "id": "prd", "source": "galeno" }
              ],
              "sendingRules": {
                "internalWrites": { "notion": "allow", "google-docs": "ask" }
              }
            }
            """

        let config = try AgentConfig.jsonDecoder.decode(AgentConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.schemaVersion, 1)
        XCTAssertEqual(config.agentName, "Hipócrates")
        XCTAssertEqual(config.language, .spanish)
        XCTAssertEqual(config.role, .productManager)

        XCTAssertEqual(config.connections.count, 2)
        XCTAssertEqual(config.connections[0].tool, .whatsapp)
        XCTAssertEqual(config.connections[0].status, .connected)
        XCTAssertFalse(config.connections[0].sources.readsEverything)
        XCTAssertEqual(config.connections[0].sources.selected.first?.kind, .group)
        XCTAssertEqual(config.connections[1].tool, .googleMeet)
        XCTAssertEqual(config.connections[1].status, .skipped)
        XCTAssertTrue(config.connections[1].sources.readsEverything)

        XCTAssertEqual(config.skills, [SelectedSkill(id: "prd", source: .galeno)])
        XCTAssertEqual(config.sendingRules.policy(for: .notion), .allow)
        XCTAssertEqual(config.sendingRules.policy(for: .googleDocs), .ask)
    }

    func testEncodesSchemaVersion() throws {
        let data = try AgentConfig.jsonEncoder.encode(AgentConfig.example)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, AgentConfig.currentSchemaVersion)
    }

    func testNewConfigUsesTheCurrentSchemaVersion() {
        let config = AgentConfig(agentName: "Galena", language: .english)

        XCTAssertEqual(config.schemaVersion, AgentConfig.currentSchemaVersion)
    }

    func testConnectedToolsExcludesSkippedAndPendingOnes() {
        let tools = AgentConfig.example.connectedTools

        XCTAssertFalse(tools.contains(.granola), "la saltada no debe contar")
        XCTAssertFalse(tools.contains(.fathom), "la que aún no se conecta no debe contar")
        XCTAssertTrue(tools.contains(.whatsapp))
        XCTAssertEqual(tools.count, Tool.allCases.count - 2)
    }

    func testConnectionLookup() {
        let config = AgentConfig.example

        XCTAssertEqual(config.connection(for: .slack)?.status, .connected)
        XCTAssertEqual(config.connection(for: .granola)?.status, .skipped)
    }

    func testAConfigWithNoConnectionsIsValidAndRoundTrips() throws {
        let config = AgentConfig(agentName: "Galena", language: .english)

        let data = try AgentConfig.jsonEncoder.encode(config)
        let decoded = try AgentConfig.jsonDecoder.decode(AgentConfig.self, from: data)

        XCTAssertEqual(decoded, config)
        XCTAssertTrue(decoded.connectedTools.isEmpty)
    }

    /// El modelo no lleva credenciales. Si alguien añade un campo de token, esto
    /// no lo atrapa, pero deja escrita la intención junto a la prueba.
    func testEncodedConfigHasNoCredentialFields() throws {
        let data = try AgentConfig.jsonEncoder.encode(AgentConfig.example)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()

        for forbidden in ["token", "secret", "password", "apikey", "credential"] {
            XCTAssertFalse(text.contains(forbidden), "el JSON no debería mencionar \(forbidden)")
        }
    }
}
