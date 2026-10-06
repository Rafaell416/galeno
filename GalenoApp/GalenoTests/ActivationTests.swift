import GalenoCore
import XCTest

@testable import Galeno

/// Lo que salió del demo de Aquiles (5 oct 2026): Galeno prepara Claude Code por su cuenta, un conector
/// nunca se marca conectado solo, la tira lleva a cada conexión y un error dice su causa de verdad.

// MARK: - Dobles

/// Un terminal que devuelve lo que se le diga y anota el comando.
private final class ScriptedTerminal: TerminalRunning, @unchecked Sendable {
    private let result: ManagedProcess.Result?
    private let lock = NSLock()
    private var recorded: [(command: String, timeout: TimeInterval)] = []

    init(_ result: ManagedProcess.Result?) { self.result = result }

    var calls: [String] { lock.withLock { recorded.map(\.command) } }

    func runInTerminal(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> ManagedProcess.Result? {
        lock.withLock { recorded.append((([executable] + arguments).joined(separator: " "), timeout)) }
        return result
    }
}

/// Instalar e iniciar sesión, con guion. Cada uno puede quedarse esperando hasta que la prueba lo suelte.
private final class FakeClaudeSetup: ClaudeCodeSettingUp, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var installOutcome: ClaudeSetupOutcome = .done
    var signInOutcome: ClaudeSetupOutcome = .done
    /// `true`: el inicio de sesión no termina hasta que se cancele (el usuario sigue en el navegador).
    var holdsSignIn = false
    /// Lo que pasa «en el Mac» cuando el instalador o el inicio de sesión terminan bien.
    var onInstalled: @Sendable () -> Void = {}
    var onSignedIn: @Sendable () -> Void = {}

    var calls: [String] { lock.withLock { recorded } }

    func install() async -> ClaudeSetupOutcome {
        lock.withLock { recorded.append("install") }
        if installOutcome == .done { onInstalled() }
        return installOutcome
    }

    func signIn(claudePath: String) async -> ClaudeSetupOutcome {
        lock.withLock { recorded.append("signIn \(claudePath)") }
        while holdsSignIn {
            if Task.isCancelled { return .cancelled }
            try? await Task.sleep(for: .milliseconds(5))
        }
        if signInOutcome == .done { onSignedIn() }
        return signInOutcome
    }
}

/// Un Mac cuyo `claude` cambia: la prueba decide qué versión hay y si tiene sesión.
private final class ChangingMac: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var version: String?
    private var loggedIn = false
    let path: String

    init(path: String, version: String?, loggedIn: Bool = false) {
        self.path = path
        self.version = version
        self.loggedIn = loggedIn
    }

    func set(version: String?) { lock.withLock { self.version = version } }
    func set(loggedIn: Bool) { lock.withLock { self.loggedIn = loggedIn } }
    var hasClaude: Bool { lock.withLock { version != nil } }

    func run(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> CommandResult? {
        lock.withLock {
            guard executable == path, let version else { return nil }
            if arguments == ["--version"] { return CommandResult(status: 0, output: "\(version) (Claude Code)") }
            if arguments == ["auth", "status"] {
                return CommandResult(status: 0, output: #"{"loggedIn": \#(loggedIn)}"#)
            }
            return nil
        }
    }
}

@MainActor
final class ActivationTests: XCTestCase {
    private let claude = "/Users/prueba/.local/bin/claude"

    private func makeState(mac: ChangingMac, setup: FakeClaudeSetup) -> WizardState {
        let detector = ClaudeCodeDetector(
            runner: mac, homeDirectory: "/Users/prueba", isExecutable: { [claude] in $0 == claude && mac.hasClaude })
        return WizardState(
            preferredLanguages: ["es"], claudeStatus: .checking, claudeDetector: detector,
            connectServices: ConnectServices(
                makeMCP: { _ in FakeMCP() }, whatsapp: FakeWhatsApp(), installer: .sandboxed(),
                fetchRealData: false, sleep: SleepLog().sleeper, claudeSetup: setup))
    }

    // MARK: - El paso 2 en un Mac sin nada

    /// La primera vez el estado es «buscando» sin que nadie haya buscado: entrar al paso tiene que mirar.
    /// Tomarlo por una búsqueda en curso dejaba el paso girando para siempre (arranque limpio, 5 oct 2026).
    func testEnteringTheStepLooksEvenThoughTheStatusStartsAsChecking() async {
        let mac = ChangingMac(path: claude, version: "2.1.289", loggedIn: true)
        let state = makeState(mac: mac, setup: FakeClaudeSetup())
        XCTAssertEqual(state.claudeStatus, .checking)

        await state.detectClaudeCodeIfNeeded()

        XCTAssertNotEqual(state.claudeStatus, .checking, "se quedó sin mirar")
        XCTAssertTrue(state.claudeStatus.isFound)
    }

    func testEnteringTheStepAgainDoesNotLookOnceItIsReady() async {
        let mac = ChangingMac(path: claude, version: "2.1.289", loggedIn: true)
        let state = makeState(mac: mac, setup: FakeClaudeSetup())
        await state.detectClaudeCodeIfNeeded()
        XCTAssertTrue(state.claudeStatus.isReady)

        // Si volviera a mirar, ya no lo encontraría: que siga listo prueba que no miró.
        mac.set(version: nil)
        await state.detectClaudeCodeIfNeeded()
        XCTAssertTrue(state.claudeStatus.isReady, "volver atrás y adelante no lo vuelve a buscar")
    }

    // MARK: - Instalar, actualizar, iniciar sesión

    func testInstallRunsTheOfficialInstallerOverHTTPSAndNothingElse() async {
        let terminal = ScriptedTerminal(ManagedProcess.Result(status: 0, output: "✅ Installation complete!", wasStopped: false))
        let outcome = await ClaudeCodeSetup(terminal: terminal).install()

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(terminal.calls.count, 1)
        let command = terminal.calls[0]
        XCTAssertTrue(command.hasPrefix("/bin/bash -c "))
        XCTAssertTrue(command.contains("https://claude.ai/install.sh"), "solo el instalador oficial")
        XCTAssertTrue(command.contains("--proto '=https'"), "solo por https")
        XCTAssertTrue(command.contains("set -o pipefail"), "un fallo de curl no se pierde tras el bash")
        XCTAssertFalse(command.contains("sudo"))
    }

    func testInstallTellsOfflineFromAFailedInstaller() async {
        func outcome(_ status: Int32, _ output: String = "", stopped: Bool = false) async -> ClaudeSetupOutcome {
            await ClaudeCodeSetup(
                terminal: ScriptedTerminal(ManagedProcess.Result(status: status, output: output, wasStopped: stopped))
            ).install()
        }
        let unresolved = await outcome(6)
        XCTAssertEqual(unresolved, .offline, "curl no resolvió el nombre")
        let refused = await outcome(7)
        XCTAssertEqual(refused, .offline)
        let failed = await outcome(1, "Checksum verification failed\n")
        XCTAssertEqual(failed, .failed("Checksum verification failed"))
        let slow = await outcome(15, stopped: true)
        XCTAssertEqual(slow, .timedOut)
        let notLaunched = await ClaudeCodeSetup(terminal: ScriptedTerminal(nil)).install()
        XCTAssertEqual(notLaunched, .failed(""))
    }

    func testSignInRunsAuthLoginWithTheClaudeGalenoFound() async {
        let terminal = ScriptedTerminal(ManagedProcess.Result(status: 0, output: "Login successful", wasStopped: false))
        let outcome = await ClaudeCodeSetup(terminal: terminal).signIn(claudePath: claude)

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(terminal.calls, ["\(claude) auth login"])
    }

    /// La salida de `claude auth login` trae la dirección de autorización: nunca llega a la pantalla.
    func testTheDetailOfAFailureNeverCarriesTheAuthorizationAddress() {
        let output = """
            Opening browser to sign in…
            If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?code=true&state=abc123
            Paste code here if prompted >
            Login failed: network error
            """
        let detail = ClaudeCodeSetup.detail(output)
        XCTAssertFalse(detail.contains("https://"))
        XCTAssertFalse(detail.contains("abc123"))
        XCTAssertTrue(detail.contains("Login failed: network error"))
    }

    /// Lo que deja de verdad el instalador al final (visto el 5 oct 2026): códigos de terminal que no son color.
    func testTheDetailIsCleanOfTerminalCodes() {
        let output = "Installing…\n\u{1B}(B\u{1B}[>4m\u{1B}[<u\u{1B}7\u{1B}8 ✅ Installation complete!\r\n"
        XCTAssertEqual(ClaudeCodeSetup.detail(output), "Installing… ✅ Installation complete!")
    }

    func testAMissingClaudeIsInstalledWithOneTap() async {
        let mac = ChangingMac(path: claude, version: nil)
        let setup = FakeClaudeSetup()
        setup.onInstalled = { mac.set(version: "2.1.289") }
        let state = makeState(mac: mac, setup: setup)
        await state.detectClaudeCode()
        XCTAssertEqual(state.claudeStatus, .notFound)

        state.installClaudeCode()
        XCTAssertEqual(state.claudeSetup, .installing)
        let done = await waitUntil { state.claudeSetup == .idle }

        XCTAssertTrue(done, "\(state.claudeSetup)")
        XCTAssertEqual(setup.calls, ["install"])
        XCTAssertEqual(state.claudeStatus, .found(version: "2.1.289", path: claude, loggedIn: false))
        XCTAssertFalse(state.claudeStatus.isReady, "recién instalado: falta la sesión")
        // Y se dice que quedó instalado antes de pedir la sesión (feedback de Aquiles, 5 oct 2026).
        XCTAssertEqual(state.claudeJustInstalledVersion, "2.1.289")
    }

    func testAnOutdatedClaudeIsUpdatedWithTheSameInstaller() async {
        let mac = ChangingMac(path: claude, version: "2.1.150", loggedIn: true)
        let setup = FakeClaudeSetup()
        setup.onInstalled = { mac.set(version: "2.1.289") }
        let state = makeState(mac: mac, setup: setup)
        await state.detectClaudeCode()
        XCTAssertEqual(state.claudeStatus, .outdated(version: "2.1.150", path: claude))

        state.installClaudeCode()
        let done = await waitUntil { state.claudeSetup == .idle }

        XCTAssertTrue(done)
        XCTAssertEqual(state.claudeStatus, .found(version: "2.1.289", path: claude, loggedIn: true))
        XCTAssertTrue(state.claudeStatus.isReady)
    }

    /// El instalador dijo que todo bien, pero sigue sin haber un Claude Code que sirva: es un fallo.
    func testAnInstallThatLeavesNothingUsableIsAFailure() async {
        let mac = ChangingMac(path: claude, version: "2.1.150")
        let state = makeState(mac: mac, setup: FakeClaudeSetup())
        await state.detectClaudeCode()

        state.installClaudeCode()
        let failed = await waitUntil { state.claudeSetup == .failed(.installFailed(detail: "")) }

        XCTAssertTrue(failed, "\(state.claudeSetup)")
    }

    func testInstallFailuresSayWhy() async {
        for (outcome, failure) in [
            (ClaudeSetupOutcome.offline, ClaudeSetupFailure.offline),
            (.timedOut, .installTimedOut),
            (.failed("Checksum verification failed"), .installFailed(detail: "Checksum verification failed")),
        ] {
            let setup = FakeClaudeSetup()
            setup.installOutcome = outcome
            let state = makeState(mac: ChangingMac(path: claude, version: nil), setup: setup)
            await state.detectClaudeCode()
            state.installClaudeCode()
            let failed = await waitUntil { state.claudeSetup == .failed(failure) }
            XCTAssertTrue(failed, "\(outcome) → \(state.claudeSetup)")
            XCTAssertEqual(state.claudeStatus, .notFound)
        }
    }

    func testSigningInLetsTheWizardGoOn() async {
        let mac = ChangingMac(path: claude, version: "2.1.289")
        let setup = FakeClaudeSetup()
        setup.onSignedIn = { mac.set(loggedIn: true) }
        let state = makeState(mac: mac, setup: setup)
        await state.detectClaudeCode()
        state.next()  // bienvenida → Claude Code
        XCTAssertEqual(state.step, .detection)
        XCTAssertFalse(state.canGoForward, "sin sesión no se sigue")

        state.signInToClaude()
        let done = await waitUntil { state.claudeSetup == .idle && state.claudeStatus.isReady }

        XCTAssertTrue(done, "\(state.claudeSetup) \(state.claudeStatus)")
        XCTAssertEqual(setup.calls, ["signIn \(claude)"])
        XCTAssertTrue(state.canGoForward)
    }

    /// «Ya inicié sesión, comprobar»: se mira ya, aunque `claude auth login` siga esperando.
    func testConfirmingASignInDoesNotWaitForTheLoginCommand() async {
        let mac = ChangingMac(path: claude, version: "2.1.289")
        let setup = FakeClaudeSetup()
        setup.holdsSignIn = true
        let state = makeState(mac: mac, setup: setup)
        await state.detectClaudeCode()
        state.signInToClaude()
        XCTAssertEqual(state.claudeSetup, .signingIn)

        // Todavía no entró: comprobar no cambia nada y la espera sigue.
        await state.confirmClaudeSignIn()
        XCTAssertEqual(state.claudeSetup, .signingIn)

        mac.set(loggedIn: true)
        await state.confirmClaudeSignIn()
        XCTAssertEqual(state.claudeSetup, .idle)
        XCTAssertTrue(state.claudeStatus.isReady)
    }

    func testCancellingASignInGoesBackToTheButton() async {
        let mac = ChangingMac(path: claude, version: "2.1.289")
        let setup = FakeClaudeSetup()
        setup.holdsSignIn = true
        let state = makeState(mac: mac, setup: setup)
        await state.detectClaudeCode()
        state.signInToClaude()

        state.cancelClaudeSetup()

        XCTAssertEqual(state.claudeSetup, .idle)
        XCTAssertEqual(state.claudeStatus, .found(version: "2.1.289", path: claude, loggedIn: false))
    }

    func testASignInThatDoesNotLeaveASessionIsAFailure() async {
        let mac = ChangingMac(path: claude, version: "2.1.289")
        let state = makeState(mac: mac, setup: FakeClaudeSetup())  // termina «bien» pero sin sesión
        await state.detectClaudeCode()
        state.signInToClaude()
        let failed = await waitUntil { state.claudeSetup == .failed(.signInFailed(detail: "")) }
        XCTAssertTrue(failed, "\(state.claudeSetup)")
    }

    /// Nada se instala por descuido: sin poner el de verdad, el servicio no hace nada.
    func testTheDefaultSetupServiceDoesNothing() async {
        let install = await NoClaudeCodeSetup().install()
        XCTAssertEqual(install, .failed(""))
    }

    // MARK: - Un error dice su causa

    func testAnOldClaudeThatDoesNotKnowMcpLoginIsNamedAsSuch() {
        XCTAssertEqual(ClaudeMCPClient.loginError("error: unknown command 'login'\n"), .claudeOutdated)
        XCTAssertEqual(
            ClaudeMCPClient.loginError("Error: OAuth flow was cancelled\n"),
            .loginFailed("Error: OAuth flow was cancelled"))
    }

    func testAnOutdatedClaudeFailsTheConnectionWithItsOwnMessage() async {
        let mcp = FakeMCP(loginFailures: ["notion": [.claudeOutdated]])
        let flow = ConnectFlow(
            tools: [.notion, .jira], mcp: mcp, whatsapp: FakeWhatsApp(), fetchRealData: false,
            sleep: SleepLog().sleeper)
        defer { flow.cancelAll() }
        flow.connect()
        let failed = await waitUntil { flow.phase == .failed(.claudeOutdated) }
        XCTAssertTrue(failed, "\(flow.phase)")
    }

    // MARK: - Conectores: solo cuenta un «conectado» de verdad

    private var openedURLs: [URL] = []

    /// Un flujo cuya espera de conectores dura lo bastante para que la prueba actúe en medio.
    private func makeConnectorFlow(_ mcp: FakeMCP, tools: [Tool] = [.gmail, .jira]) -> ConnectFlow {
        openedURLs = []
        return ConnectFlow(
            tools: tools, mcp: mcp, whatsapp: FakeWhatsApp(), fetchRealData: false,
            timing: ConnectFlow.Timing(connectorPoll: 1, connectorMax: 300, connectorPendingLooks: 1),
            sleep: { duration in
                // El tramo de la espera dura de verdad un poco; lo demás (el éxito de 1,5 s) se detiene.
                if duration == .seconds(0.5) {
                    try? await Task.sleep(for: .milliseconds(4))
                } else if duration == .milliseconds(1500) {
                    try? await Task.sleep(for: .seconds(30))
                }
            },
            openURL: { [unowned self] in openedURLs.append($0) })
    }

    /// El caso de Aquiles: pulsó «Conectar» en Claude y se quedó eligiendo cuenta. El conector sale
    /// «pendiente» una y otra vez, y Galeno **no** lo marca.
    func testWaitingInTheBrowserNeverTurnsIntoConnected() async {
        let mcp = FakeMCP(statuses: [:])  // no está en la cuenta
        let flow = makeConnectorFlow(mcp)
        defer { flow.cancelAll() }
        flow.connect()
        let waiting = await waitUntil { flow.isWaitingForConnector }
        XCTAssertTrue(waiting, "\(flow.phase)")
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://claude.ai/directory/gmail-gmailmcp"])

        mcp.setStatus("claude.ai Gmail", .pending)  // ya pulsó «Conectar»; sigue en el selector de cuentas
        try? await Task.sleep(for: .milliseconds(300))  // muchas miradas seguidas en «pendiente»

        XCTAssertTrue(flow.isWaitingForConnector, "sigue esperando: \(flow.phase)")
        XCTAssertNotEqual(flow.statuses[.gmail], .connected)

        mcp.setStatus("claude.ai Gmail", .connected)  // terminó de verdad
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }
        XCTAssertTrue(done, "\(flow.phase)")
    }

    /// «Ya lo conecté, comprobar» con el conector aún sin autorizar: se dice que todavía no, y se sigue esperando.
    func testConfirmingTooEarlySaysNotYetAndKeepsWaiting() async {
        let mcp = FakeMCP(statuses: ["claude.ai Gmail": .needsAuthentication])
        let flow = makeConnectorFlow(mcp)
        defer { flow.cancelAll() }
        flow.connect()
        let waiting = await waitUntil { flow.isWaitingForConnector }
        XCTAssertTrue(waiting)

        flow.confirmConnector()
        let notYet = await waitUntil { flow.connectorCheck == .notYet }

        XCTAssertTrue(notYet, "\(flow.connectorCheck)")
        XCTAssertTrue(flow.isWaitingForConnector)
        XCTAssertNotEqual(flow.statuses[.gmail], .connected)
    }

    /// «Ya lo conecté» con el conector «pendiente»: ahí sí vale, porque lo afirma el usuario (es la salida
    /// del cuelgue del demo de Felipe, sin que el tiempo marque nada).
    func testConfirmingAPendingConnectorAcceptsIt() async {
        let mcp = FakeMCP(statuses: ["claude.ai Gmail": .pending])
        let flow = makeConnectorFlow(mcp)
        defer { flow.cancelAll() }
        flow.connect()
        let waiting = await waitUntil { flow.isWaitingForConnector }
        XCTAssertTrue(waiting, "\(flow.phase)")
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("authorize") })

        flow.confirmConnector()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(flow.statuses[.gmail], .connected)
    }

    func testThePageCanBeOpenedAgainWhileWaiting() async {
        let flow = makeConnectorFlow(FakeMCP(statuses: [:]))
        defer { flow.cancelAll() }
        flow.reopenConnectorPage()
        XCTAssertTrue(openedURLs.isEmpty, "sin espera en curso no abre nada")

        flow.connect()
        _ = await waitUntil { flow.isWaitingForConnector }
        flow.reopenConnectorPage()

        XCTAssertEqual(openedURLs.count, 2)
        XCTAssertEqual(openedURLs.last?.absoluteString, "https://claude.ai/directory/gmail-gmailmcp")
    }

    // MARK: - La tira lleva a cada conexión

    private func makeFlow(_ tools: [Tool], statuses: [Tool: ConnectionStatus] = [:], mcp: FakeMCP = FakeMCP())
        -> ConnectFlow
    {
        ConnectFlow(
            tools: tools, statuses: statuses, mcp: mcp, whatsapp: FakeWhatsApp(), fetchRealData: false,
            sleep: SleepLog.holdingSuccess.sleeper)
    }

    func testAnIconTakesYouToItsConnection() {
        let flow = makeFlow([.notion, .jira, .fathom])
        defer { flow.cancelAll() }
        XCTAssertEqual(flow.screen, .connection(.notion))
        XCTAssertTrue(flow.canJump(to: .fathom))
        XCTAssertFalse(flow.canJump(to: .notion), "ya se está en ella")

        flow.jump(to: .fathom)

        XCTAssertEqual(flow.screen, .connection(.fathom))
        XCTAssertEqual(flow.phase, .ready)
        XCTAssertEqual(flow.statuses[.notion] ?? .selected, .selected, "la que se dejó no queda saltada")
    }

    func testAConnectedToolIsNotAPlaceToGo() {
        let flow = makeFlow([.notion, .jira, .fathom], statuses: [.jira: .connected])
        defer { flow.cancelAll() }
        XCTAssertFalse(flow.canJump(to: .jira))
        flow.jump(to: .jira)
        XCTAssertEqual(flow.screen, .connection(.notion))
    }

    /// Lo que se dejó atrás al saltar no se pierde: antes de celebrar se vuelve por ello.
    func testWhatWasLeftBehindComesBackBeforeTheEnd() {
        let flow = makeFlow([.notion, .jira])
        defer { flow.cancelAll() }
        flow.jump(to: .jira)
        flow.skip()  // Jira, la última: saltada

        XCTAssertEqual(flow.screen, .connection(.notion), "falta Notion: no se celebra todavía")
        XCTAssertFalse(flow.isFinished)

        flow.skip()
        XCTAssertTrue(flow.isFinished)
    }

    /// Lo que ya se resolvió saltando no se vuelve a enseñar al pasar por su sitio.
    func testWhatWasResolvedOutOfOrderIsNotShownAgain() {
        let flow = makeFlow([.notion, .jira, .fathom])
        defer { flow.cancelAll() }
        flow.jump(to: .fathom)
        flow.skip()  // Fathom, la última, resuelta: se vuelve por lo que falta
        XCTAssertEqual(flow.screen, .connection(.notion))
        flow.skip()
        XCTAssertEqual(flow.screen, .connection(.jira))
        flow.skip()
        if case .dopamine = flow.screen { flow.continueFromDopamine() }  // la pausa de siempre

        XCTAssertTrue(flow.isFinished, "no vuelve a Fathom: \(flow.screen)")
    }

    func testASkippedToolCanBeTakenUpAgainFromTheStrip() async {
        let mcp = FakeMCP(statuses: ["notion": .connected])
        let flow = makeFlow([.notion, .jira], mcp: mcp)
        defer { flow.cancelAll() }
        flow.skip()  // Notion saltada
        XCTAssertEqual(flow.screen, .connection(.jira))
        XCTAssertTrue(flow.canJump(to: .notion))

        flow.jump(to: .notion)
        flow.connect()
        let done = await waitUntil { flow.statuses[.notion] == .connected }

        XCTAssertTrue(done, "\(flow.phase)")
    }

    /// En el orden de siempre nada cambia: una tras otra y al final la celebración.
    func testGoingInOrderStillEndsInTheCelebration() {
        let flow = makeFlow([.notion, .jira])
        defer { flow.cancelAll() }
        flow.skip()
        XCTAssertEqual(flow.screen, .connection(.jira))
        flow.skip()
        XCTAssertTrue(flow.isFinished)
    }

    // MARK: - El wizard corto y «Gestionar» no conectan con un Claude Code que no sirve

    func testAClaudeInstalledMidwayReplacesTheConnectFlow() async {
        let mac = ChangingMac(path: claude, version: nil)
        let setup = FakeClaudeSetup()
        setup.onInstalled = {
            mac.set(version: "2.1.289")
            mac.set(loggedIn: true)
        }
        let state = makeState(mac: mac, setup: setup)
        await state.detectClaudeCode()
        state.toggle(.notion)
        state.beginConnecting()
        let first = state.connectFlow

        state.installClaudeCode()
        _ = await waitUntil { state.claudeStatus.isReady }
        state.beginConnecting()

        XCTAssertFalse(state.connectFlow === first, "el sub-wizard viejo apuntaba a un `claude` que no estaba")
        XCTAssertEqual(state.claudePath, claude)
    }
}

/// Lo que se lee mientras algo tarda (`WaitingTicker`): una función del tiempo, sin estado.
final class WaitingScriptTests: XCTestCase {
    private let lines = ["Descargando.", "Tarda un minuto.", "Mientras tanto.", "Sigue en marcha."]

    func testEachLineIsTypedLetterByLetterAndThenStays() {
        let start = WaitingScript.frame(elapsed: 0, lines: lines, interval: 5)
        XCTAssertEqual(start, .init(index: 0, visible: 0, isComplete: false))

        let typing = WaitingScript.frame(elapsed: 0.1, lines: lines, interval: 5)
        XCTAssertEqual(typing.index, 0)
        XCTAssertTrue((1..<lines[0].count).contains(typing.visible), "a medio escribir: \(typing.visible)")

        let resting = WaitingScript.frame(elapsed: 4.9, lines: lines, interval: 5)
        XCTAssertEqual(resting, .init(index: 0, visible: lines[0].count, isComplete: true), "nunca más letras de las que hay")
    }

    func testLinesFollowOneAnotherAndTheLoopSkipsTheOpeningOnes() {
        XCTAssertEqual(WaitingScript.frame(elapsed: 5.5, lines: lines, interval: 5).index, 1)
        XCTAssertEqual(WaitingScript.frame(elapsed: 19, lines: lines, interval: 5).index, 3)
        // Acabada la lista, no vuelve a «Descargando»: repite desde la tercera.
        let looped = (4...9).map { WaitingScript.frame(elapsed: Double($0) * 5 + 1, lines: lines, interval: 5, loopFrom: 2).index }
        XCTAssertEqual(looped, [2, 3, 2, 3, 2, 3])
    }

    func testOddInputsNeverCrash() {
        XCTAssertEqual(WaitingScript.frame(elapsed: 3, lines: [], interval: 5).visible, 0)
        XCTAssertEqual(WaitingScript.frame(elapsed: -4, lines: lines, interval: 5).index, 0)
        XCTAssertEqual(WaitingScript.frame(elapsed: 999, lines: ["Sola."], interval: 5, loopFrom: 7).index, 0)
        XCTAssertEqual(WaitingScript.frame(elapsed: 3, lines: lines, interval: 0).index, 0)
    }

    func testTheClockReadsMinutesAndSeconds() {
        XCTAssertEqual(WaitingScript.clock(7.9), "0:07")
        XCTAssertEqual(WaitingScript.clock(102), "1:42")
        XCTAssertEqual(WaitingScript.clock(-3), "0:00")
    }

    /// Las frases de cada espera existen en los dos idiomas y ninguna promete un porcentaje ni un final.
    func testTheWaitingLinesAreWrittenInBothLanguages() throws {
        let app = Bundle(for: WizardState.self)
        let keys =
            (1...3).map { "wait.check.\($0)" } + (1...7).map { "wait.install.\($0)" } + (1...3).map { "wait.signin.\($0)" }
            + ["wait.slow"]
        for language in ["es", "en"] {
            let bundle = try XCTUnwrap(Bundle(path: try XCTUnwrap(app.path(forResource: language, ofType: "lproj"))))
            for key in keys {
                let text = bundle.localizedString(forKey: key, value: "⟂", table: nil)
                XCTAssertNotEqual(text, "⟂", "\(key) no está en \(language)")
                XCTAssertFalse(text.contains("!") || text.contains("%"), "\(key): \(text)")
            }
        }
    }
}

/// Cuándo se da por cargada la app de Claude antes de mandarle un enlace (`ClaudeAppLoad`).
final class ClaudeAppLoadTests: XCTestCase {
    func testOnlyTheProcessesInsideTheAppBundleCount() {
        let ps = """
              1.2 /Applications/Claude.app/Contents/MacOS/Claude
             31,5 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)
             80.0 /Users/prueba/Library/Application Support/Claude/claude-code/2.1.286/claude.app/Contents/MacOS/claude
             12.0 /Applications/Claude Imitador.app/Contents/MacOS/Claude
              0.0 /usr/sbin/cfprefsd
            """
        XCTAssertEqual(ClaudeAppLoad.total(psOutput: ps, bundlePath: "/Applications/Claude.app"), 32.7, accuracy: 0.001)
        XCTAssertEqual(ClaudeAppLoad.total(psOutput: "", bundlePath: "/Applications/Claude.app"), 0)
    }

    func testWithoutAReadingItIsNotQuiet() {
        XCTAssertFalse(ClaudeAppLoad.isQuiet(nil), "sin lectura se sigue esperando")
        XCTAssertTrue(ClaudeAppLoad.isQuiet(3))
        XCTAssertFalse(ClaudeAppLoad.isQuiet(140))
    }
}
