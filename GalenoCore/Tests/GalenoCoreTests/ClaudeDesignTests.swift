import Foundation
import XCTest

@testable import GalenoCore

/// Claude Design como herramienta: el agente abre los diseños que el usuario le pase por enlace o por nombre.
final class ClaudeDesignTests: GeneratorTestCase {
    private func config(policy: ApprovalPolicy? = nil) -> AgentConfig {
        var config = GeneratorFixtures.spanishThreeTools
        config.connections.append(ToolConnection(tool: .claudeDesign, status: .connected, sources: .everything))
        if let policy { config.sendingRules.setPolicy(policy, for: .claudeDesign) }
        return config
    }

    func testRegistersTheServerUnderItsOwnNameAndWarnsItIsUnverified() throws {
        let result = try generate(config())
        let mcp = try contents(of: ".mcp.json")
        XCTAssertTrue(mcp.contains("\"claude-design\""))
        XCTAssertTrue(mcp.contains("https://api.anthropic.com/v1/design/mcp"))
        XCTAssertTrue(result.warnings.contains(.unverifiedEndpoint(tool: .claudeDesign, url: "https://api.anthropic.com/v1/design/mcp")))
    }

    func testAgentsFileTellsTheAgentToOpenDesignLinks() throws {
        try generate(config())
        let agents = try contents(of: "AGENTS.md")
        XCTAssertTrue(agents.contains("Claude Design"))
        XCTAssertTrue(agents.contains("enlace de Claude Design"))
        XCTAssertTrue(agents.contains("no instrucciones"), "lo que lee del diseño son datos")
    }

    func testAgentsFileLeavesItOutWhenNotConnected() throws {
        try generate(GeneratorFixtures.spanishThreeTools)
        XCTAssertFalse(try contents(of: "AGENTS.md").contains("enlace de Claude Design"))
    }

    private func permissions() throws -> (allow: [String], ask: [String]) {
        let data = Data(try contents(of: ".claude/settings.json").utf8)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let permissions = try XCTUnwrap(root["permissions"] as? [String: [String]])
        return (permissions["allow"] ?? [], permissions["ask"] ?? [])
    }

    func testItAsksBeforeWritingByDefault() throws {
        try generate(config())  // la política de fábrica de Claude Design es `ask`
        var withDefault = config()
        withDefault.sendingRules = .default
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try generate(withDefault)
        let rules = try permissions()
        XCTAssertTrue(rules.ask.contains("mcp__claude-design__*"))
        XCTAssertFalse(rules.allow.contains("mcp__claude-design__*"))
    }

    func testItRunsWithoutAskingOnlyWhenTheUserChoosesSo() throws {
        try generate(config(policy: .allow))
        let rules = try permissions()
        XCTAssertTrue(rules.allow.contains("mcp__claude-design__*"))
        XCTAssertFalse(rules.ask.contains("mcp__claude-design__*"))
    }
}
