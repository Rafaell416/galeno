import XCTest

@testable import Galeno

/// El estado de un conector de la cuenta de Claude se lee del arranque de una sesión, no de `claude mcp get`.
final class ClaudeSessionProbeTests: XCTestCase {
    private let initEvent = Data(
        #"""
        {"type":"system","subtype":"init","mcp_servers":[{"name":"github","status":"connected","source":"user"},{"name":"claude.ai Google Drive","status":"needs-auth","source":"claudeai"},{"name":"claude.ai Notion","status":"connected","source":"claudeai"},{"name":"claude.ai Lovable","status":"pending","source":"claudeai"}],"tools":["Read"]}
        """#.utf8)

    func testReadsTheStatusOfEveryServerFromTheInitEvent() throws {
        let statuses = try XCTUnwrap(ClaudeSessionProbe.parseInit(initEvent))
        XCTAssertEqual(statuses["claude.ai Google Drive"], "needs-auth")
        XCTAssertEqual(statuses["claude.ai Notion"], "connected")
        XCTAssertEqual(statuses.count, 4)
    }

    func testOtherEventsAreNotTheInitEvent() {
        XCTAssertNil(ClaudeSessionProbe.parseInit(Data(#"{"type":"system","subtype":"hook_started"}"#.utf8)))
        XCTAssertNil(ClaudeSessionProbe.parseInit(Data(#"{"type":"assistant"}"#.utf8)))
        XCTAssertNil(ClaudeSessionProbe.parseInit(Data("no es json".utf8)))
    }

    /// `needs-auth` no es «conectado», que es justo lo que `claude mcp get` confunde. Lo que no aparece no
    /// está en la cuenta; `pending` es «todavía no se sabe».
    func testTheStatusMapsToWhatTheFlowNeeds() throws {
        let statuses = try XCTUnwrap(ClaudeSessionProbe.parseInit(initEvent))
        XCTAssertEqual(ClaudeMCPClient.connectorStatus(of: "claude.ai Google Drive", in: statuses), .needsAuthentication)
        XCTAssertEqual(ClaudeMCPClient.connectorStatus(of: "claude.ai Notion", in: statuses), .connected)
        XCTAssertEqual(ClaudeMCPClient.connectorStatus(of: "claude.ai Gmail", in: statuses), .notRegistered)
        XCTAssertEqual(ClaudeMCPClient.connectorStatus(of: "claude.ai Lovable", in: statuses), .failed)
    }
}
