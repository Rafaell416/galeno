import XCTest

@testable import GalenoCore

final class MCPServerCatalogTests: XCTestCase {
    private func definitions(for tool: Tool) -> [MCPServerDefinition] {
        MCPServerCatalog.definitions(for: tool, whatsAppBridgePath: "/bin/galeno-whatsapp")
    }

    func testGoogleWorkspaceReturnsExactlyThreeServers() {
        let servers = definitions(for: .googleWorkspace).map(\.serverName).sorted()

        XCTAssertEqual(servers, ["google-docs", "google-drive", "google-sheets"])
    }

    /// Google Meet no tiene MCP propio: sus transcripciones se leen por Drive.
    func testGoogleMeetReturnsNoServers() {
        XCTAssertEqual(definitions(for: .googleMeet), [])
    }

    func testEveryOtherToolReturnsExactlyOneServer() {
        for tool in Tool.allCases where tool != .googleWorkspace && tool != .googleMeet {
            XCTAssertEqual(definitions(for: tool).count, 1, "\(tool)")
        }
    }

    /// La investigación cerró las cinco dudas que había. La única excepción es Claude Design, que se añadió
    /// a propósito sin que su endpoint esté documentado (lo inyecta Claude Code solo): ver el siguiente test.
    func testEveryCatalogEntryIsVerifiedExceptClaudeDesign() {
        for tool in Tool.allCases where tool != .claudeDesign {
            for server in definitions(for: tool) {
                XCTAssertTrue(server.endpointIsVerified, "\(tool) · \(server.serverName)")
            }
        }
    }

    func testClaudeDesignIsTheOnlyUnverifiedEndpointAndKeepsItsOwnName() {
        let servers = definitions(for: .claudeDesign)
        XCTAssertEqual(servers.map(\.serverName), ["claude-design"], "no choca con el `claude_design` que inyecta Claude Code")
        XCTAssertEqual(servers.map(\.endpointIsVerified), [false])
    }

    func testEveryHTTPEndpointUsesHTTPS() {
        for tool in Tool.allCases {
            for server in definitions(for: tool) {
                if case let .http(url) = server.transport {
                    XCTAssertTrue(url.hasPrefix("https://"), "\(tool) · \(server.serverName)")
                }
            }
        }
    }

    /// La v1/sse de Jira se apaga el 30 de junio de 2026; no debe reaparecer.
    func testJiraUsesTheCurrentEndpoint() {
        let jira = definitions(for: .jira)
        XCTAssertEqual(jira.map(\.transport), [.http(url: "https://mcp.atlassian.com/v2/mcp")])
    }

    func testWhatsAppIsTheOnlyLocalServer() {
        let local = Tool.allCases.filter { tool in
            definitions(for: tool).contains { if case .stdio = $0.transport { true } else { false } }
        }
        XCTAssertEqual(local, [.whatsapp])
    }

    /// Las herramientas marcadas `requiresUserProvidedOAuthClient` son
    /// exactamente las que el catálogo sabe resolver; una sin la otra dejaría
    /// al renderer sin saber qué hacer.
    func testOAuthClientRequirementMatchesTheToolFlag() {
        XCTAssertEqual(
            Tool.allCases.filter(\.requiresUserProvidedOAuthClient).sorted {
                $0.rawValue < $1.rawValue
            },
            [.gmail, .googleWorkspace, .slack]
        )
    }
}
