import XCTest

@testable import GalenoCore

final class MCPServerCatalogTests: XCTestCase {
    private func definitions(for tool: Tool) -> [MCPServerDefinition] {
        MCPServerCatalog.definitions(for: tool, whatsAppBridgePath: "/bin/galeno-whatsapp")
    }

    /// Google se usa por los conectores de la cuenta de Claude: Claude Code los trae solos y nombra sus
    /// herramientas `mcp__claude_ai_<Nombre>__…`. No hay nada que registrar ni dirección que escribir.
    func testGoogleGoesThroughTheClaudeAccountConnectors() {
        let workspace = definitions(for: .googleWorkspace)
        XCTAssertEqual(
            workspace.map(\.serverName), ["claude_ai_Google_Drive", "claude_ai_Google_Docs", "claude_ai_Google_Sheets"])
        XCTAssertEqual(
            workspace.map(\.transport),
            [
                .claudeConnector(name: "Google Drive", directorySlug: "google-drive-drivemcp"),
                .claudeConnector(name: "Google Docs", directorySlug: "google-docs-docsmcp"),
                .claudeConnector(name: "Google Sheets", directorySlug: "google-sheets-sheetsmcp"),
            ])

        XCTAssertEqual(definitions(for: .gmail).map(\.serverName), ["claude_ai_Gmail"])
        XCTAssertEqual(
            definitions(for: .gmail).map(\.transport), [.claudeConnector(name: "Gmail", directorySlug: "gmail-gmailmcp")])
        XCTAssertEqual(
            definitions(for: .googleCalendar).map(\.transport),
            [.claudeConnector(name: "Google Calendar", directorySlug: "google-calendar-calendarmcp")])
    }

    /// Los cinco conectores de Google se vieron en una cuenta real (4 de octubre de 2026): cada uno trae
    /// sus listas, y ninguna herramienta está en dos.
    func testEveryGoogleConnectorIsVerifiedAndBringsItsToolLists() {
        let google = [Tool.gmail, .googleWorkspace, .googleCalendar].flatMap { definitions(for: $0) }
        XCTAssertEqual(
            google.filter(\.endpointIsVerified).map(\.serverName),
            [
                "claude_ai_Gmail", "claude_ai_Google_Drive", "claude_ai_Google_Docs", "claude_ai_Google_Sheets",
                "claude_ai_Google_Calendar",
            ])
        XCTAssertEqual(
            google.map { $0.readOnlyTools.count + $0.writeTools.count + $0.alwaysAskTools.count + $0.draftTools.count },
            [30, 11, 2, 9, 9])
        for server in google {
            XCTAssertFalse(server.readOnlyTools.isEmpty, "\(server.serverName) trae su lista de lecturas")
            XCTAssertTrue(
                Set(server.readOnlyTools).isDisjoint(with: server.writeTools + server.alwaysAskTools + server.draftTools))
            XCTAssertTrue(Set(server.draftTools).isDisjoint(with: server.writeTools + server.alwaysAskTools))
            for tool in server.readOnlyTools {
                for verb in ["create", "update", "delete", "send", "respond", "unlabel", "label_", "insert", "share", "trash"] {
                    XCTAssertFalse(tool.contains(verb), "\(server.serverName): \(tool) contiene «\(verb)»")
                }
            }
        }
    }

    /// Las 12 de Fathom salen de una cuenta real (4 oct 2026) y todas leen: no tiene escrituras.
    func testTheFathomToolsAreTwelveAndAllReadOnly() throws {
        let fathom = try XCTUnwrap(definitions(for: .fathom).first)
        XCTAssertEqual(fathom.readOnlyTools.count, 12)
        XCTAssertEqual(Set(fathom.readOnlyTools).count, 12)
        XCTAssertTrue(fathom.writeTools.isEmpty)
        XCTAssertTrue(fathom.alwaysAskTools.isEmpty)
        for tool in fathom.readOnlyTools {
            for verb in ["create", "update", "delete", "share", "send", "add", "remove", "edit"] {
                XCTAssertFalse(tool.contains(verb), "\(tool) contiene «\(verb)»")
            }
        }
    }

    /// Las listas de Jira salen de una cuenta real (4 oct 2026): 12 que leen, 7 que escriben con la regla del
    /// usuario y 2 que siempre preguntan. Ninguna repetida, y entre las que leen no hay nada que cree, cambie,
    /// borre ni ejecute escrituras.
    func testTheJiraToolListsAreDisjointAndTheReadOnesOnlyRead() throws {
        let jira = try XCTUnwrap(definitions(for: .jira).first)
        let all = jira.readOnlyTools + jira.writeTools + jira.alwaysAskTools
        XCTAssertEqual(all.count, 21)
        XCTAssertEqual(Set(all).count, 21)
        XCTAssertEqual(Set(jira.alwaysAskTools), ["executeDestructive", "executeWrite"])
        for tool in jira.readOnlyTools {
            for verb in ["create", "update", "edit", "add", "transition", "delete", "Write", "Destructive"] {
                XCTAssertFalse(tool.contains(verb), "\(tool) contiene «\(verb)»")
            }
        }
    }

    /// Las listas del conector de Drive salen de una cuenta real: 6 que leen, 3 que escriben con la
    /// regla del usuario y 2 que siempre preguntan. Ninguna repetida, y entre las que leen no hay
    /// nada que cree, cambie, comparta o borre.
    func testTheGoogleDriveToolListsAreDisjointAndTheReadOnesOnlyRead() throws {
        let drive = try XCTUnwrap(definitions(for: .googleWorkspace).first)
        let all = drive.readOnlyTools + drive.writeTools + drive.alwaysAskTools
        XCTAssertEqual(all.count, 11)
        XCTAssertEqual(Set(all).count, 11)
        XCTAssertEqual(Set(drive.alwaysAskTools), ["share_file", "trash_file"])
        for tool in drive.readOnlyTools {
            for verb in ["create", "update", "copy", "share", "trash", "delete", "move", "upload"] {
                XCTAssertFalse(tool.contains(verb), "\(tool) contiene «\(verb)»")
            }
        }
    }

    /// Google Meet no tiene MCP propio: sus transcripciones se leen por Drive.
    func testGoogleMeetReturnsNoServers() {
        XCTAssertEqual(definitions(for: .googleMeet), [])
    }

    func testEveryOtherToolReturnsExactlyOneServer() {
        // Google Workspace son tres conectores (Drive, Docs, Sheets); Meet no tiene ninguno.
        for tool in Tool.allCases where tool != .googleWorkspace && tool != .googleMeet {
            XCTAssertEqual(definitions(for: tool).count, 1, "\(tool)")
        }
    }

    /// La excepción: Claude Design, que se añadió a propósito sin que su endpoint esté documentado (lo
    /// inyecta Claude Code solo).
    func testEveryCatalogEntryIsVerifiedExceptClaudeDesign() {
        for tool in Tool.allCases where tool != .claudeDesign {
            for server in definitions(for: tool) {
                XCTAssertTrue(server.endpointIsVerified, "\(tool) · \(server.serverName)")
            }
        }
    }

    /// Gmail envía: `send_message`, `reply` y `forward` existen en el conector real y nunca pueden
    /// quedar entre las lecturas ni los borradores (irían sin preguntar).
    func testTheGmailToolsThatSendAreNeverReadsNorDrafts() {
        let gmail = definitions(for: .gmail)[0]
        for tool in ["send_message", "reply", "forward", "trash_thread", "delete_draft"] {
            XCTAssertTrue(gmail.writeTools.contains(tool), tool)
            XCTAssertFalse(gmail.readOnlyTools.contains(tool), tool)
            XCTAssertFalse(gmail.draftTools.contains(tool), tool)
        }
        XCTAssertEqual(
            gmail.readOnlyTools, ["get_draft", "get_message", "get_thread", "list_drafts", "list_labels", "search_threads"])
        // Preparar un borrador no envía: va sin preguntar (tareas programadas, docs/03 §3b). Solo estas dos.
        XCTAssertEqual(gmail.draftTools, ["create_draft", "update_draft"])
        // Y nadie más tiene borradores: la excepción es de Gmail.
        for tool in Tool.allCases where tool != .gmail {
            for server in MCPServerCatalog.definitions(for: ToolConnection(tool: tool), whatsAppBridgePath: "/b") {
                XCTAssertTrue(server.draftTools.isEmpty, "\(tool)")
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
            [.slack]
        )
    }
}
