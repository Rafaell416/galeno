import Foundation
import XCTest

@testable import GalenoCore

/// Cuentas por agente (GAL-13): una herramienta puede tener más de una cuenta, cada una con su identidad.
///
/// Lo que no puede pasar: que una cuenta extra se quede sin su regla de aprobación o sin su hook (un envío sin
/// preguntar, línea roja 3), que una instalación de antes cambie de nombre de servidor, o que `.mcp.json` de
/// la cuenta de siempre se mueva.
final class AccountsTests: XCTestCase {
    private let prefix = MCPServerCatalog.ownedNamePrefix

    private func connection(
        _ tool: Tool, account: String? = nil, name: String? = nil, clientID: String? = nil
    ) -> ToolConnection {
        ToolConnection(
            tool: tool, status: .connected, sources: .everything, oauthClientID: clientID,
            serverNamePrefix: prefix, accountID: account, accountName: name)
    }

    private func config(_ connections: [ToolConnection]) -> AgentConfig {
        AgentConfig(agentName: "Hera", language: .spanish, connections: connections)
    }

    // MARK: - Identificador

    func testTheSlugKeepsOnlyLowercaseLettersDigitsAndDashes() {
        XCTAssertEqual(AccountID.slug(from: "Trabajo"), "trabajo")
        XCTAssertEqual(AccountID.slug(from: "  Mi cuenta personal  "), "mi-cuenta-personal")
        XCTAssertEqual(AccountID.slug(from: "Compañía S.A."), "compania-s-a")
        XCTAssertNil(AccountID.slug(from: "   "))
        XCTAssertNil(AccountID.slug(from: "!!!"))
    }

    func testTheSlugIsBoundedAndNeverEndsInADash() throws {
        let slug = try XCTUnwrap(AccountID.slug(from: String(repeating: "ab ", count: 30)))
        XCTAssertLessThanOrEqual(slug.count, AccountID.maxLength)
        XCTAssertFalse(slug.hasSuffix("-"))
        XCTAssertTrue(AccountID.isValid(slug))
    }

    /// El identificador acaba en un patrón (`^mcp__galeno-notion-<id>__…`): nada que un patrón interprete.
    func testNothingThatBreaksAPatternIsAValidIdentifier() {
        for bad in ["a.b", "a*", "a|b", "a)", "(?!x", "A", "a b", "-a", "a-", "", "a/b", "ñ"] {
            XCTAssertFalse(AccountID.isValid(bad), "«\(bad)» no debería ser válido")
        }
        XCTAssertTrue(AccountID.isValid("trabajo-2"))
    }

    // MARK: - Identidad de la conexión

    func testTwoAccountsOfTheSameToolHaveDifferentIDs() {
        let personal = connection(.notion)
        let work = connection(.notion, account: "trabajo", name: "Trabajo")
        XCTAssertNotEqual(personal.id, work.id)
        XCTAssertEqual(personal.id, ConnectionID(tool: .notion))
        XCTAssertEqual(work.id, ConnectionID(tool: .notion, account: "trabajo"))
    }

    func testConnectionLookupPrefersTheDefaultAccount() throws {
        let value = config([connection(.notion, account: "trabajo", name: "Trabajo"), connection(.notion)])
        XCTAssertNil(try XCTUnwrap(value.connection(for: .notion)).accountID)
        XCTAssertEqual(value.connections(for: .notion).count, 2)
        XCTAssertEqual(value.connectedTools, [.notion], "la herramienta cuenta una vez")
    }

    func testDisplayNameCarriesTheAccountName() {
        XCTAssertEqual(connection(.notion).displayName(in: .spanish), "Notion")
        XCTAssertEqual(
            connection(.notion, account: "trabajo", name: "Trabajo").displayName(in: .spanish), "Notion (Trabajo)")
    }

    func testOnlyToolsGalenoRegistersSupportMoreAccounts() {
        for tool in [Tool.notion, .jira, .slack] { XCTAssertTrue(tool.supportsMultipleAccounts) }
        for tool in [Tool.whatsapp, .gmail, .googleWorkspace, .googleCalendar, .googleMeet, .claudeDesign] {
            XCTAssertFalse(tool.supportsMultipleAccounts)
        }
        // Toda herramienta que admite más cuentas es una que Galeno registra con su prefijo.
        for tool in Tool.allCases where tool.supportsMultipleAccounts {
            XCTAssertNotNil(MCPServerCatalog.defaultNamePrefix(for: tool), "\(tool) no lleva prefijo propio")
        }
    }

    // MARK: - Servidores

    func testAnExtraAccountIsItsOwnServerAndTheDefaultKeepsItsName() {
        let defaultNames = MCPServerCatalog.definitions(for: connection(.notion), whatsAppBridgePath: "")
            .map(\.serverName)
        let extraNames = MCPServerCatalog.definitions(
            for: connection(.notion, account: "trabajo", name: "Trabajo"), whatsAppBridgePath: ""
        ).map(\.serverName)
        XCTAssertEqual(defaultNames, ["galeno-notion"])
        XCTAssertEqual(extraNames, ["galeno-notion-trabajo"])
    }

    func testAccountsKeepGalenoOwnership() {
        let extra = connection(.jira, account: "cliente-a", name: "Cliente A")
        XCTAssertTrue(extra.galenoOwnsServers)
        XCTAssertTrue(
            MCPServerCatalog.definitions(for: extra, whatsAppBridgePath: "").allSatisfy {
                $0.serverName.hasPrefix(MCPServerCatalog.ownedNamePrefix)
            })
    }

    /// Un identificador mal formado (un archivo editado a mano) no llega al nombre del servidor.
    func testAnInvalidAccountIDNeverReachesTheServerName() {
        let bad = connection(.notion, account: "x.*|y", name: "x")
        XCTAssertEqual(
            MCPServerCatalog.definitions(for: bad, whatsAppBridgePath: "").map(\.serverName), ["galeno-notion"])
    }

    func testAToolThatDoesNotSupportAccountsIgnoresTheAccountID() {
        let weird = ToolConnection(
            tool: .gmail, status: .connected, serverNamePrefix: prefix, accountID: "otra", accountName: "Otra")
        let names = MCPServerCatalog.definitions(for: weird, whatsAppBridgePath: "").map(\.serverName)
        XCTAssertEqual(names, [MCPServerCatalog.claudeConnectorServerName("Gmail")])
    }

    func testNoServerNameCollidesAcrossToolsAndAccounts() {
        var names: [String] = []
        for tool in Tool.allCases {
            for account in [nil, "trabajo", "personal"] {
                let conn = connection(tool, account: account, name: account, clientID: "1234567890123.1234567890123")
                names += MCPServerCatalog.definitions(for: conn, whatsAppBridgePath: "/x").map(\.serverName)
            }
        }
        // Las cuentas de herramientas que no las admiten colapsan en la misma; lo que importa es que ninguna
        // cuenta extra pise el servidor de otra herramienta.
        let extras = names.filter { $0.hasSuffix("-trabajo") || $0.hasSuffix("-personal") }
        for extra in extras {
            let base = extra.replacingOccurrences(of: "-trabajo", with: "").replacingOccurrences(of: "-personal", with: "")
            XCTAssertTrue(names.contains(base), "\(extra) debe colgar de un servidor que existe")
            XCTAssertEqual(names.filter { $0 == extra }.count, 1)
        }
    }

    // MARK: - Lo generado

    func testMCPJSONHasOneServerPerAccountAndTheDefaultIsUnchanged() throws {
        let both = try MCPRenderer.render(
            config([connection(.notion), connection(.notion, account: "trabajo", name: "Trabajo")]),
            whatsAppBridgePath: ""
        ).json
        let only = try MCPRenderer.render(config([connection(.notion)]), whatsAppBridgePath: "").json
        XCTAssertTrue(both.contains("\"galeno-notion\""))
        XCTAssertTrue(both.contains("\"galeno-notion-trabajo\""))
        XCTAssertTrue(only.contains("\"galeno-notion\""))
        XCTAssertFalse(only.contains("galeno-notion-trabajo"))
    }

    /// El punto que importa: la cuenta extra de Slack lleva **su propia** regla de aprobación y su propio hook.
    func testAnExtraSlackAccountGetsItsOwnApprovalRulesAndHook() throws {
        let value = config([
            connection(.slack, clientID: "1234567890123.1234567890123"),
            connection(.slack, account: "cliente-a", name: "Cliente A", clientID: "1234567890123.1234567890123"),
        ])
        let settings = try SettingsRenderer.render(value)
        XCTAssertTrue(settings.contains("mcp__galeno-slack__slack_send_message"))
        XCTAssertTrue(settings.contains("mcp__galeno-slack-cliente-a__slack_send_message"), "la regla ask de la cuenta extra")
        XCTAssertTrue(settings.contains("mcp__galeno-slack-cliente-a__slack_read_channel"), "sus lecturas")
        XCTAssertTrue(settings.contains("^mcp__galeno-slack-cliente-a__(?!"), "su hook de aprobación")
        XCTAssertEqual(
            SettingsRenderer.serversRequiringApproval(in: value).sorted(),
            ["galeno-slack", "galeno-slack-cliente-a"])
    }

    /// Un envío por la cuenta extra no puede quedar libre porque la de siempre ya estaba cubierta: está en `ask`,
    /// y ningún permiso `allow` cubre su servidor entero.
    func testTheExtraAccountsSendsAskAndNothingAllowsItsWholeServer() throws {
        let value = config([
            connection(.slack, clientID: "1234567890123.1234567890123"),
            connection(.slack, account: "cliente-a", name: "Cliente A", clientID: "1234567890123.1234567890123"),
        ])
        let data = Data(try SettingsRenderer.render(value).utf8)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let permissions = try XCTUnwrap(root["permissions"] as? [String: Any])
        let allow = try XCTUnwrap(permissions["allow"] as? [String])
        let ask = try XCTUnwrap(permissions["ask"] as? [String])

        for write in MCPServerCatalog.slackWriteTools {
            XCTAssertTrue(ask.contains("mcp__galeno-slack-cliente-a__\(write)"), "\(write) debe preguntar")
            XCTAssertFalse(allow.contains("mcp__galeno-slack-cliente-a__\(write)"), "\(write) no debe ir libre")
        }
        XCTAssertFalse(allow.contains { $0.hasPrefix("mcp__galeno-slack-cliente-a__") && $0.hasSuffix("*") })
        XCTAssertFalse(allow.contains("mcp__galeno-slack-cliente-a"), "ni el servidor entero")
    }

    func testSubagentsGrantTheExtraAccountOnlyWhereTheDefaultIsGranted() {
        let value = config([
            connection(.notion), connection(.notion, account: "trabajo", name: "Trabajo"),
            connection(.slack, clientID: "1234567890123.1234567890123"),
            connection(.slack, account: "cliente-a", name: "Cliente A", clientID: "1234567890123.1234567890123"),
        ])
        let granted = SubagentsRenderer.grantedServers(in: value)
        XCTAssertTrue(granted.contains("galeno-notion"))
        XCTAssertTrue(granted.contains("galeno-notion-trabajo"))
        XCTAssertFalse(granted.contains { $0.hasPrefix("galeno-slack") }, "los subagentes no llegan a las que envían")
    }

    func testTheGeneratedAgentsFileNamesEachAccount() throws {
        let value = config([connection(.notion), connection(.notion, account: "trabajo", name: "Trabajo")])
        let text = AgentsFileRenderer.render(value)
        XCTAssertTrue(text.contains("**Notion** —"))
        XCTAssertTrue(text.contains("**Notion (Trabajo)** —"))
    }

    func testToolsReadingWithoutAskingListsEachToolOnce() {
        let value = config([
            connection(.slack, clientID: "1234567890123.1234567890123"),
            connection(.slack, account: "cliente-a", name: "Cliente A", clientID: "1234567890123.1234567890123"),
        ])
        XCTAssertEqual(value.toolsReadingWithoutAsking, [.slack])
    }

    // MARK: - Compatibilidad con lo guardado

    func testAConfigSavedBeforeAccountsDecodesAndEncodesTheSame() throws {
        let legacy = """
            {"tool":"notion","status":"connected","sources":{"readsEverything":true,"selected":[]},\
            "serverNamePrefix":"galeno-"}
            """
        let decoded = try JSONDecoder().decode(ToolConnection.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.accountID)
        XCTAssertNil(decoded.accountName)
        XCTAssertEqual(decoded.id, ConnectionID(tool: .notion))

        let reencoded = try String(decoding: JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(reencoded.contains("accountID"), "una cuenta de siempre no escribe nada nuevo")
        XCTAssertFalse(reencoded.contains("accountName"))
    }

    func testTheAccountSurvivesASaveAndLoad() throws {
        let original = connection(.jira, account: "cliente-a", name: "Cliente A")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ToolConnection.self, from: data), original)
    }

    // MARK: - Instalación

    func testTheInstallationKeepsOneSharedConnectionPerAccount() {
        var installation = GalenoInstallation(language: .spanish)
        installation.setConnection(SharedConnection(tool: .notion, status: .connected, serverNamePrefix: prefix))
        installation.setConnection(
            SharedConnection(
                tool: .notion, status: .connected, serverNamePrefix: prefix, accountID: "trabajo",
                accountName: "Trabajo"))
        XCTAssertEqual(installation.connections(for: .notion).count, 2)
        XCTAssertNil(installation.connection(for: .notion)?.accountID, "la de siempre es la que se pide por herramienta")
        XCTAssertNotNil(installation.connection(for: ConnectionID(tool: .notion, account: "trabajo")))

        // Volver a guardar la misma cuenta la reemplaza, no la duplica.
        installation.setConnection(
            SharedConnection(
                tool: .notion, status: .skipped, serverNamePrefix: prefix, accountID: "trabajo",
                accountName: "Trabajo"))
        XCTAssertEqual(installation.connections(for: .notion).count, 2)
        XCTAssertEqual(installation.connection(for: ConnectionID(tool: .notion, account: "trabajo"))?.status, .skipped)
    }

    func testANewAgentStartsWithTheDefaultAccountsOnly() {
        var installation = GalenoInstallation(language: .spanish)
        installation.setConnection(SharedConnection(tool: .notion, status: .connected, serverNamePrefix: prefix))
        installation.setConnection(
            SharedConnection(
                tool: .notion, status: .connected, serverNamePrefix: prefix, accountID: "trabajo",
                accountName: "Trabajo"))
        let start = installation.startingPoint(agentName: "Hera")
        XCTAssertEqual(start.connections.count, 1)
        XCTAssertNil(start.connections.first?.accountID)
    }

    func testResolvedConfigTakesEachAccountsStateFromItsOwnSharedConnection() throws {
        var installation = GalenoInstallation(language: .spanish)
        installation.setConnection(SharedConnection(tool: .notion, status: .connected, serverNamePrefix: prefix))
        installation.setConnection(
            SharedConnection(
                tool: .notion, status: .skipped, serverNamePrefix: prefix, accountID: "trabajo",
                accountName: "Trabajo"))
        let record = installation.addAgent(
            config([connection(.notion), connection(.notion, account: "trabajo", name: "Trabajo")]),
            agentsRoot: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let resolved = try XCTUnwrap(installation.resolvedConfig(for: record.id))
        XCTAssertEqual(resolved.connection(for: ConnectionID(tool: .notion))?.status, .connected)
        XCTAssertEqual(resolved.connection(for: ConnectionID(tool: .notion, account: "trabajo"))?.status, .skipped)
    }
}
