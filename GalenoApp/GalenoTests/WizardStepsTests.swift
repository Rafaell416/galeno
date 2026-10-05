import AppKit
import GalenoCore
import XCTest

@testable import Galeno

/// Las pantallas 2, 3 y 4: qué bloquea "Siguiente" y cómo se comporta la grilla.
@MainActor
final class WizardStepsTests: XCTestCase {
    private func advance(_ state: WizardState, to step: WizardStep) {
        for _ in 0..<20 where state.step != step && state.canGoForward { state.next() }
        XCTAssertEqual(state.step, step)
    }

    // MARK: - Paso 2: Claude Code

    func testTheDetectionStepBlocksUntilClaudeIsFound() {
        let state = WizardState(preferredLanguages: ["es"], claudeStatus: .notFound)
        advance(state, to: .detection)

        XCTAssertFalse(state.canGoForward)
        state.next()
        XCTAssertEqual(state.step, .detection)
    }

    func testTheDetectionStepBlocksWhileChecking() {
        let state = WizardState(preferredLanguages: ["es"], claudeStatus: .checking)
        advance(state, to: .detection)

        XCTAssertFalse(state.canGoForward)
    }

    /// Sin sesión no se sigue: las conexiones fallarían una por una (demo de Aquiles, 5 oct 2026).
    func testAMissingSessionBlocksUntilSignedIn() {
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.289", path: "/ruta/claude", loggedIn: false))
        advance(state, to: .detection)

        XCTAssertFalse(state.canGoForward)
    }

    func testAnOutdatedClaudeBlocks() {
        let state = WizardState(
            preferredLanguages: ["es"], claudeStatus: .outdated(version: "2.1.150", path: "/ruta/claude"))
        advance(state, to: .detection)

        XCTAssertFalse(state.canGoForward)
    }

    func testASessionThatCannotBeReadDoesNotBlock() {
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.289", path: "/ruta/claude", loggedIn: nil))
        advance(state, to: .detection)

        XCTAssertTrue(state.canGoForward)
    }

    func testDetectingClaudeUpdatesTheStatus() async {
        let path = "/opt/homebrew/bin/claude"
        let found = ClaudeCodeDetector(
            runner: StubRunner(version: "2.1.289 (Claude Code)"),
            homeDirectory: "/Users/prueba",
            isExecutable: { $0 == path })
        let state = WizardState(preferredLanguages: ["es"], claudeStatus: .notFound, claudeDetector: found)

        await state.detectClaudeCode()

        XCTAssertEqual(state.claudeStatus, .found(version: "2.1.289", path: path, loggedIn: nil))
    }

    // MARK: - Paso 3: el agente

    func testAnEmptyOrBlankNameIsAnIssueAndBlocks() {
        let state = readyState()
        advance(state, to: .agent)

        for name in ["", "   ", "\n \t"] {
            state.agentName = name
            XCTAssertEqual(state.agentNameIssue, .empty, "\(name.debugDescription)")
            XCTAssertFalse(state.canGoForward)
        }
    }

    func testANameOfSixtyCharactersIsFineAndSixtyOneIsNot() {
        let state = readyState()
        advance(state, to: .agent)

        state.agentName = String(repeating: "a", count: WizardState.maxAgentNameLength)
        XCTAssertNil(state.agentNameIssue)
        XCTAssertTrue(state.canGoForward)

        state.agentName = String(repeating: "a", count: WizardState.maxAgentNameLength + 1)
        XCTAssertEqual(state.agentNameIssue, .tooLong)
        XCTAssertFalse(state.canGoForward)
    }

    func testSurroundingSpacesDoNotCountTowardTheLimit() {
        let state = readyState()
        state.agentName = "  " + String(repeating: "a", count: WizardState.maxAgentNameLength) + "  "

        XCTAssertNil(state.agentNameIssue)
    }

    func testTheProjectDescriptionIsOptional() {
        let state = readyState()
        advance(state, to: .agent)
        state.agentName = "Aurora"
        state.projectDescription = ""

        XCTAssertTrue(state.canGoForward)
    }

    // MARK: - Paso 4: las herramientas

    func testTheToolsStepNeedsAtLeastOneTool() {
        let state = readyState()
        advance(state, to: .tools)
        for tool in state.selectedTools { state.toggle(tool) }  // desmarca todo

        XCTAssertTrue(state.connections.isEmpty)
        XCTAssertFalse(state.canGoForward)

        state.toggle(.slack)
        XCTAssertTrue(state.canGoForward)
    }

    func testTogglingAddsAndRemovesATool() {
        let state = WizardState(preferredLanguages: ["es"])

        state.toggle(.slack)
        XCTAssertTrue(state.isSelected(.slack))
        XCTAssertEqual(state.connections, [ToolConnection(tool: .slack, status: .selected)])

        state.toggle(.slack)
        XCTAssertFalse(state.isSelected(.slack))
        XCTAssertTrue(state.connections.isEmpty)
    }

    /// El orden de la grilla es el del rol: en producto, Notion va antes que Fathom y WhatsApp al final.
    func testSelectedToolsFollowTheOrderOfTheGridNotTheOrderOfTheClicks() {
        let state = WizardState(preferredLanguages: ["es"])

        state.toggle(.fathom)
        state.toggle(.whatsapp)
        state.toggle(.notion)

        XCTAssertEqual(state.selectedTools, [.notion, .fathom, .whatsapp])

        state.role = .sales
        state.toggle(.slack)
        XCTAssertEqual(state.selectedTools, [.whatsapp, .slack, .notion, .fathom], "y en comercial, WhatsApp primero")
    }

    // MARK: - Paso 1: el rol

    func testLeavingTheRoleStepTicksItsFirstThreeTools() {
        let state = WizardState(
            preferredLanguages: ["es"], claudeStatus: .found(version: "2.1.289", path: "/ruta/claude", loggedIn: true))
        XCTAssertEqual(state.step, .role)
        XCTAssertTrue(state.canGoForward, "el rol viene elegido: producto")

        state.next()
        XCTAssertEqual(state.selectedTools, [.jira, .notion, .slack])
    }

    func testChangingTheRoleBeforeTouchingTheToolsChangesTheProposal() {
        let state = WizardState(
            preferredLanguages: ["es"], claudeStatus: .found(version: "2.1.289", path: "/ruta/claude", loggedIn: true))
        state.next()
        state.back()
        state.role = .sales
        state.next()
        XCTAssertEqual(state.selectedTools, [.whatsapp, .gmail, .googleWorkspace])
        XCTAssertEqual(state.makeConfig().role, .sales)
    }

    func testAChoiceTheUserMadeIsNotReplacedByTheRole() {
        let state = WizardState(
            preferredLanguages: ["es"], claudeStatus: .found(version: "2.1.289", path: "/ruta/claude", loggedIn: true))
        state.next()
        state.toggle(.fathom)
        state.back()
        state.role = .marketing
        state.next()
        XCTAssertTrue(state.isSelected(.fathom), "lo que el usuario marcó se queda")
        XCTAssertEqual(Set(state.selectedTools), [.jira, .notion, .slack, .fathom])
        XCTAssertEqual(state.selectedTools.first, .slack, "pero en el orden del rol nuevo")
    }

    func testMeetBringsGoogleWorkspaceAlong() {
        let state = WizardState(preferredLanguages: ["es"])

        state.toggle(.googleMeet)

        XCTAssertEqual(state.selectedTools, [.googleWorkspace, .googleMeet])
        XCTAssertTrue(state.isRequiredBySelection(.googleWorkspace))
    }

    func testGoogleWorkspaceCannotBeUnticketedWhileMeetNeedsIt() {
        let state = WizardState(preferredLanguages: ["es"])
        state.toggle(.googleMeet)

        state.toggle(.googleWorkspace)
        XCTAssertTrue(state.isSelected(.googleWorkspace))

        // Quitando Meet, Workspace queda marcada pero ya se puede quitar.
        state.toggle(.googleMeet)
        XCTAssertEqual(state.selectedTools, [.googleWorkspace])
        state.toggle(.googleWorkspace)
        XCTAssertTrue(state.connections.isEmpty)
    }

    func testMeetDoesNotDuplicateWorkspaceWhenItIsAlreadySelected() {
        let state = WizardState(preferredLanguages: ["es"])
        state.toggle(.googleWorkspace)

        state.toggle(.googleMeet)

        XCTAssertEqual(state.selectedTools, [.googleWorkspace, .googleMeet])
    }

    func testTheEstimateAddsUpPerTool() {
        let state = WizardState(preferredLanguages: ["es"])
        XCTAssertEqual(state.estimatedSetupMinutes, 1, "mínimo 1 minuto")

        for tool in [Tool.whatsapp, .slack, .notion, .gmail, .jira] { state.toggle(tool) }
        // 3 + 2 + 1 + 1 + 1 (Gmail va por el conector de la cuenta de Claude: un minuto)
        XCTAssertEqual(state.estimatedSetupMinutes, 8)
    }

    func testMeetCostsNothingOnTopOfWorkspace() {
        XCTAssertEqual(ToolEstimate.minutes(for: [.googleWorkspace, .googleMeet]), Tool.googleWorkspace.estimatedSetupMinutes)
    }

    func testTheSelectionBecomesConnectionsInTheConfig() {
        let state = readyState()
        state.toggle(.slack)

        let config = state.makeConfig()

        XCTAssertEqual(config.connections.map(\.tool), [.notion, .slack])
        XCTAssertTrue(config.connections.allSatisfy { $0.status == .selected })
    }

    // MARK: - Los logos

    func testEveryToolHasALogoOrASymbol() {
        for tool in Tool.allCases {
            switch tool.iconSource {
            case .asset(let name):
                XCTAssertNotNil(
                    Bundle(for: WizardState.self).image(forResource: name), "\(tool): falta el asset \(name)")
            case .symbol(let name):
                XCTAssertNotNil(
                    NSImage(systemSymbolName: name, accessibilityDescription: nil),
                    "\(tool): el símbolo \(name) no existe")
            }
        }
    }

    // MARK: - Ayudas

    /// Claude Code encontrado, un nombre y una herramienta (`.notion`).
    private func readyState() -> WizardState {
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true))
        state.agentName = "Aurora"
        state.toggle(.notion)
        return state
    }
}

/// Responde solo a `--version`; el resto (zsh, auth status) no tiene respuesta.
private struct StubRunner: CommandRunning {
    let version: String

    func run(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> CommandResult? {
        arguments == ["--version"] ? CommandResult(status: 0, output: version) : nil
    }
}
