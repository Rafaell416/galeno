import XCTest

@testable import Galeno

/// Un sondeo que devuelve, en orden, lo que se le dé (y repite el último).
private final class ScriptedProbe: SessionProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [[String: String]?]
    private var count = 0

    init(_ script: [[String: String]?]) { self.script = script }

    var calls: Int { lock.withLock { count } }

    func serverStatuses(claudePath: String) async -> [String: String]? {
        lock.withLock {
            count += 1
            return script.count > 1 ? script.removeFirst() : script[0]
        }
    }
}

/// El estado de un conector de la cuenta de Claude, leído del arranque de una sesión. Lo que falló en el demo
/// de Felipe (4 oct 2026): un conector **ya conectado** se leyó como «no está» o «pendiente», Galeno abrió su
/// página —que decía «conectado»— y se quedó esperando.
final class ConnectorStatusTests: XCTestCase {
    private let google = [
        "claude.ai Google Drive": "connected", "claude.ai Google Docs": "connected",
        "claude.ai Google Sheets": "connected", "claude.ai Gmail": "needs-auth", "github": "connected",
    ]

    private func client(_ probe: ScriptedProbe, lifetime: TimeInterval = 6) -> ClaudeMCPClient {
        ClaudeMCPClient(claudePath: "/ruta/claude", probe: probe, sessionStatuses: SessionStatusCache(lifetime: lifetime))
    }

    /// El arranque a veces da su estado antes de que llegue la lista de conectores de claude.ai: no trae
    /// ninguno. Eso no es «no está en la cuenta»: se vuelve a mirar.
    func testAStartupWithoutAnyAccountConnectorIsLookedAtAgain() async {
        let probe = ScriptedProbe([["github": "connected"], google])
        let status = await client(probe).connectorStatus("claude.ai Google Drive")
        XCTAssertEqual(status, .connected)
        XCTAssertEqual(probe.calls, 2)
    }

    /// Una cuenta que de verdad no tiene conectores: tras mirar varias veces, no está.
    func testAnAccountWithoutConnectorsIsBelievedAfterAFewLooks() async {
        let probe = ScriptedProbe([["github": "connected"]])
        let status = await client(probe).connectorStatus("claude.ai Google Drive")
        XCTAssertEqual(status, .notRegistered)
        XCTAssertEqual(probe.calls, ClaudeMCPClient.accountListAttempts)
    }

    /// Si la lista llegó y el conector no está en ella, no está: no hace falta mirar más.
    func testAConnectorMissingFromALoadedListIsNotInTheAccount() async {
        let probe = ScriptedProbe([google])
        let status = await client(probe).connectorStatus("claude.ai Google Calendar")
        XCTAssertEqual(status, .notRegistered)
        XCTAssertEqual(probe.calls, 1)
    }

    func testEachStatusKeepsItsMeaning() async {
        let probe = ScriptedProbe([google.merging(["claude.ai Lovable": "pending", "claude.ai Rota": "failed"]) { $1 }])
        let client = client(probe)
        let gmail = await client.connectorStatus("claude.ai Gmail")
        let lovable = await client.connectorStatus("claude.ai Lovable")
        let broken = await client.connectorStatus("claude.ai Rota")
        XCTAssertEqual(gmail, .needsAuthentication)
        XCTAssertEqual(lovable, .pending)
        XCTAssertEqual(broken, .failed)
    }

    /// Drive, Docs y Sheets se miran uno tras otro: comparten un solo arranque, no tres.
    func testConsecutiveConnectorsShareOneStartup() async {
        let probe = ScriptedProbe([google])
        let client = client(probe)
        for name in ["claude.ai Google Drive", "claude.ai Google Docs", "claude.ai Google Sheets"] {
            let status = await client.connectorStatus(name)
            XCTAssertEqual(status, .connected, name)
        }
        XCTAssertEqual(probe.calls, 1)
    }

    /// Pasado un momento se vuelve a arrancar: así se ve que el usuario ya autorizó.
    func testAfterAMomentTheStartupIsReadAgain() async {
        let probe = ScriptedProbe([google, google.merging(["claude.ai Gmail": "connected"]) { $1 }])
        let client = client(probe, lifetime: 0)
        let before = await client.connectorStatus("claude.ai Gmail")
        let after = await client.connectorStatus("claude.ai Gmail")
        XCTAssertEqual(before, .needsAuthentication)
        XCTAssertEqual(after, .connected)
        XCTAssertEqual(probe.calls, 2)
    }

    func testAStartupThatCannotBeReadIsUnknownNotMissing() async {
        let probe = ScriptedProbe([nil])
        let status = await client(probe).connectorStatus("claude.ai Gmail")
        XCTAssertEqual(status, .failed)
    }

    /// Lo que se le pide a Claude Code para que el estado sea el de verdad: sin la caché de descubrimiento
    /// (con ella, un conector que ya se usó sale `pending` siempre) y esperando a que conecten.
    func testTheProbeAsksClaudeCodeForTheRealStatus() {
        XCTAssertEqual(ClaudeSessionProbe.environment["MCP_DISCOVERY_CACHE"], "0")
        XCTAssertEqual(ClaudeSessionProbe.environment["MCP_CONNECTION_NONBLOCKING"], "0")
        XCTAssertNotNil(Int(ClaudeSessionProbe.environment["MCP_CONNECT_TIMEOUT_MS"] ?? ""))
    }
}
