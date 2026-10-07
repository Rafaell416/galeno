import AppKit
import XCTest

@testable import Galeno

final class WhatsAppBridgeTests: XCTestCase {
    // MARK: - Lo que imprime el bridge

    func testParsesStatus() throws {
        XCTAssertEqual(
            try WhatsAppBridge.parseLinkState("Vinculado como 573001234567.\n"), .linked(number: "573001234567"))
        XCTAssertEqual(
            try WhatsAppBridge.parseLinkState("Sin vincular. Corre: galeno-whatsapp pair\n"), .notLinked)
    }

    // MARK: - La bandeja de salida

    /// La forma exacta de `galeno-whatsapp outbox --json` (bridge 0.4.0).
    func testParsesTheOutbox() throws {
        let json = """
            {
              "paused": true,
              "limits": {
                "daily_total": 30, "daily_new_chats": 15, "daily_groups": 4,
                "max_daily_total": 80, "max_daily_new_chats": 25, "max_daily_groups": 20
              },
              "today": { "sent": 12, "pending": 3, "new_chats": 7, "groups": 2 },
              "pending_total": 5,
              "recent": [
                { "id": 15, "chat_jid": "573001112233@s.whatsapp.net", "status": "pending", "is_new_chat": true,
                  "created_at": "2026-10-07T10:02:11-05:00", "not_before": "2026-10-07T10:03:40-05:00" }
              ]
            }
            """

        let outbox = try XCTUnwrap(WhatsAppBridge.parseOutbox(jsonOutput: json))

        XCTAssertTrue(outbox.isPaused)
        XCTAssertEqual(
            outbox.limits,
            WhatsAppOutbox.Limits(
                dailyTotal: 30, dailyNewChats: 15, dailyGroups: 4, maxDailyTotal: 80, maxDailyNewChats: 25,
                maxDailyGroups: 20))
        XCTAssertEqual(outbox.sentToday, 12)
        XCTAssertEqual(outbox.pendingToday, 3)
        XCTAssertEqual(outbox.usedToday, 15)
        XCTAssertEqual(outbox.newChatsToday, 7)
        XCTAssertEqual(outbox.groupsToday, 2)
        XCTAssertEqual(outbox.pendingTotal, 5)
    }

    /// Un bridge anterior a la 0.4.0 no conoce `outbox`, y otro programa no es el bridge: no se inventa nada.
    func testAnOutboxThatIsNotTheExpectedShapeIsNotGuessed() {
        XCTAssertNil(WhatsAppBridge.parseOutbox(jsonOutput: ""))
        XCTAssertNil(WhatsAppBridge.parseOutbox(jsonOutput: "Subcomando desconocido: outbox"))
        XCTAssertNil(WhatsAppBridge.parseOutbox(jsonOutput: #"{"paused":false}"#))
    }

    private func bridge(stateDirectory: URL) -> WhatsAppBridge {
        WhatsAppBridge(
            installer: BridgeInstaller(source: nil, destination: URL(fileURLWithPath: "/bridge/galeno-whatsapp")),
            runner: FakeRunner([:]), stateDirectory: stateDirectory)
    }

    /// La pausa y los límites son dos archivos en el directorio de estado del bridge, con los nombres que él mira.
    func testPauseAndLimitsAreTheFilesTheBridgeLooksAt() async throws {
        let state = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeno-bridge-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: state) }
        let bridge = bridge(stateDirectory: state)
        let pause = state.appendingPathComponent("send-paused")
        let limits = state.appendingPathComponent("send-limits.json")

        try await bridge.setSendingPaused(true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pause.path))
        try await bridge.setSendingPaused(true)  // dos veces no falla
        try await bridge.setSendingPaused(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pause.path))
        try await bridge.setSendingPaused(false)  // quitar una pausa que no hay tampoco

        try await bridge.setSendLimits(dailyTotal: 10, dailyNewChats: 3, dailyGroups: 0)
        let written = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: limits)) as? [String: Int])
        XCTAssertEqual(written, ["daily_total": 10, "daily_new_chats": 3, "daily_groups": 0])
    }

    func testParsesStatusEvenWithLogNoiseAround() throws {
        let noisy = "2026/10/03 INFO abriendo bases\nVinculado como 573001234567.\notro log\n"

        XCTAssertEqual(try WhatsAppBridge.parseLinkState(noisy), .linked(number: "573001234567"))
    }

    func testStatusThatIsNeitherThrows() {
        XCTAssertThrowsError(try WhatsAppBridge.parseLinkState("")) { error in
            XCTAssertEqual(error as? WhatsAppBridgeError, .unexpectedOutput(""))
        }
        XCTAssertThrowsError(try WhatsAppBridge.parseLinkState("panic: algo salió mal"))
    }

    func testPairOutcome() {
        func result(_ status: Int32, _ output: String, stopped: Bool = false) -> ManagedProcess.Result {
            ManagedProcess.Result(status: status, output: output, wasStopped: stopped)
        }
        XCTAssertEqual(WhatsAppBridge.pairOutcome(result(0, "Escanea...\nVinculado correctamente.\n")), .succeeded)
        XCTAssertEqual(
            WhatsAppBridge.pairOutcome(result(0, "Ya hay una sesión vinculada (573001234567). Para vincular otra...")),
            .succeeded, "sale con 0 aunque ya hubiera sesión")
        XCTAssertEqual(
            WhatsAppBridge.pairOutcome(result(1, "se agotó el tiempo esperando que escanearas el QR")),
            .failed("se agotó el tiempo esperando que escanearas el QR"))
        XCTAssertEqual(WhatsAppBridge.pairOutcome(result(15, "", stopped: true)), .failed("se agotó el tiempo"))
        XCTAssertEqual(
            WhatsAppBridge.pairOutcome(result(0, "nada que ver")), .failed("nada que ver"),
            "con 0 pero sin el texto de éxito no se da por vinculado")
    }

    func testParseChatCountsSeparatesGroupsFromIndividualChats() {
        let json = """
            [{"jid":"1@g.us","name":"A","is_group":true},
             {"jid":"2@s.whatsapp.net","name":"B","is_group":false},
             {"jid":"3@g.us","name":"","is_group":true},
             {"jid":"4@s.whatsapp.net","name":"D"}]
            """

        XCTAssertEqual(WhatsAppBridge.parseChatCounts(jsonOutput: json), ChatCounts(total: 4, groups: 2))
        XCTAssertEqual(WhatsAppBridge.parseChatCounts(jsonOutput: "[]"), ChatCounts(total: 0, groups: 0))
        XCTAssertNil(WhatsAppBridge.parseChatCounts(jsonOutput: "null"))
        XCTAssertNil(WhatsAppBridge.parseChatCounts(jsonOutput: "Uso: galeno-whatsapp chats --json"))
    }

    func testRecognisesACompletePNGAndRejectsAHalfWrittenOne() throws {
        let png = Self.makePNG(seed: 1)

        XCTAssertTrue(WhatsAppBridge.isCompletePNG(png))
        XCTAssertFalse(WhatsAppBridge.isCompletePNG(png.prefix(png.count / 2)), "a medio escribir")
        XCTAssertFalse(WhatsAppBridge.isCompletePNG(Data()))
        XCTAssertFalse(WhatsAppBridge.isCompletePNG(Data("no soy un png".utf8)))
        XCTAssertFalse(WhatsAppBridge.isCompletePNG(png.suffix(png.count - 8)), "sin la firma")
    }

    // MARK: - Empaquetado y ruta estable

    func testTheInstalledCopyLivesInApplicationSupportNotInTheApp() {
        let path = BridgeLocation.installedBinary.path

        XCTAssertTrue(path.hasSuffix("Library/Application Support/Galeno/bin/galeno-whatsapp"))
        XCTAssertFalse(path.contains("DerivedData"))
        XCTAssertFalse(path.contains(".app/"))
    }

    func testTheBridgeDirectoryMatchesWhatTheGoBinaryUses() {
        // `cli.go`: ~/Library/Application Support/Galeno/whatsapp, y el PNG se llama pair-qr.png.
        XCTAssertTrue(BridgeLocation.stateDirectory.path.hasSuffix("Library/Application Support/Galeno/whatsapp"))
        XCTAssertEqual(BridgeLocation.qrFilename, "pair-qr.png")
    }

    func testADebugFlagOverridesThePackagedBinary() {
        let url = BridgeLocation.packagedBinary(
            arguments: ["Galeno", "-galeno-bridge-path", "/tmp/otro/galeno-whatsapp"], environment: [:])

        XCTAssertEqual(url?.path, "/tmp/otro/galeno-whatsapp")
    }

    func testInstallerCopiesTheBridgeToTheStablePath() async throws {
        let sandbox = try Sandbox()
        let installer = BridgeInstaller(source: try sandbox.makeBridge(version: "0.2.0"), destination: sandbox.installed)

        try await installer.ensureInstalled()

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: sandbox.installed.path))
        let version = try await sandbox.run(sandbox.installed, "version")
        XCTAssertEqual(version, "0.2.0")
    }

    func testInstallerDoesNotCopyAgainWhenTheVersionIsTheSame() async throws {
        let sandbox = try Sandbox()
        let source = try sandbox.makeBridge(version: "0.2.0")
        let installer = BridgeInstaller(source: source, destination: sandbox.installed)
        try await installer.ensureInstalled()
        // Un marcador dentro de la copia: si se vuelve a copiar, desaparece.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: sandbox.installed.path)

        try await installer.ensureInstalled()

        let modified = try FileManager.default.attributesOfItem(atPath: sandbox.installed.path)[.modificationDate] as? Date
        XCTAssertEqual(modified, Date(timeIntervalSince1970: 0))
    }

    func testInstallerReplacesTheCopyWhenTheBridgeIsUpdated() async throws {
        let sandbox = try Sandbox()
        try await BridgeInstaller(source: try sandbox.makeBridge(version: "0.2.0"), destination: sandbox.installed).ensureInstalled()

        try await BridgeInstaller(source: try sandbox.makeBridge(version: "0.3.0"), destination: sandbox.installed).ensureInstalled()

        let version = try await sandbox.run(sandbox.installed, "version")
        XCTAssertEqual(version, "0.3.0")
    }

    func testInstallerFailsWhenThereIsNoBridgeAnywhere() async throws {
        let sandbox = try Sandbox()
        let installer = BridgeInstaller(source: nil, destination: sandbox.installed)

        do {
            try await installer.ensureInstalled()
            XCTFail("debía fallar")
        } catch {
            XCTAssertEqual(error as? WhatsAppBridgeError, .bridgeMissing)
        }
    }

    func testInstallerFallsBackToTheCopyThatWasAlreadyThere() async throws {
        let sandbox = try Sandbox()
        try await BridgeInstaller(source: try sandbox.makeBridge(version: "0.2.0"), destination: sandbox.installed).ensureInstalled()

        try await BridgeInstaller(source: nil, destination: sandbox.installed).ensureInstalled()
    }

    // MARK: - El bridge de punta a punta (con un bridge de mentira)

    func testPairingEndToEndAgainstAFakeBridge() async throws {
        let sandbox = try Sandbox()
        let bridge = try sandbox.makeWhatsAppBridge()
        try await bridge.prepare()

        let before = try await bridge.linkState()
        XCTAssertEqual(before, .notLinked)

        var events: [WhatsAppPairEvent] = []
        for await event in bridge.pair() { events.append(event) }

        let codes = events.compactMap { event -> Data? in if case .qr(let data) = event { data } else { nil } }
        XCTAssertGreaterThanOrEqual(codes.count, 2, "el QR se entrega cada vez que cambia: \(events)")
        XCTAssertNotEqual(codes.first, codes.last)
        XCTAssertTrue(codes.allSatisfy(WhatsAppBridge.isCompletePNG))
        XCTAssertEqual(events.last, .succeeded)

        let after = try await bridge.linkState()
        XCTAssertEqual(after, .linked(number: "573001234567"))

        try await bridge.installLaunchd()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.state.appendingPathComponent("launchd").path))

        let counts = await bridge.chatCounts()
        XCTAssertEqual(counts, ChatCounts(total: 2, groups: 1))
    }

    func testStoppingTheStreamStopsThePairProcess() async throws {
        let sandbox = try Sandbox()
        let bridge = try sandbox.makeWhatsAppBridge(pairSeconds: 30)
        try await bridge.prepare()
        let registry = ProcessRegistry.shared
        let before = registry.count

        let task = Task { for await _ in bridge.pair() {} }
        let started = await eventually { registry.count > before }
        XCTAssertTrue(started, "pair debería estar corriendo")

        task.cancel()
        _ = await task.value
        let stopped = await eventually { registry.count == before }
        XCTAssertTrue(stopped, "cancelar debe detener el proceso, no dejarlo escuchando")
    }

    func testTheAppOnlyEverRunsReadOnlyBridgeCommands() async throws {
        let sandbox = try Sandbox()
        let bridge = try sandbox.makeWhatsAppBridge()
        try await bridge.prepare()
        _ = try await bridge.linkState()
        for await _ in bridge.pair() {}
        try await bridge.installLaunchd()
        _ = await bridge.chatCounts()

        let log = try String(contentsOf: sandbox.state.appendingPathComponent("calls.log"), encoding: .utf8)
        let subcommands = Set(log.split(whereSeparator: \.isNewline).map { $0.split(separator: " ").first.map(String.init) ?? "" })

        XCTAssertTrue(subcommands.isSubset(of: ["version", "status", "pair", "install-launchd", "chats"]), "\(subcommands)")
        XCTAssertFalse(log.lowercased().contains("send"))
    }

    // MARK: - Al arrancar la app tras una actualización

    func testRefreshDoesNothingWhenWhatsAppWasNeverInstalled() async throws {
        let sandbox = try Sandbox()
        let launchd = FakeRunner([Sandbox.launchctlPrint: ok("\tstate = running\n")])
        let bridge = sandbox.makeBridgeToRefresh(packaged: try sandbox.makeLoggingBridge(version: "0.4.0"), launchd: launchd)

        let outcome = await bridge.refreshAfterAppUpdate()

        XCTAssertEqual(outcome, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.installed.path), "no se instala lo que nadie pidió")
        XCTAssertEqual(launchd.calls, [])
        XCTAssertEqual(sandbox.loggedCalls, [], "ni siquiera se le pregunta la versión al empaquetado")
    }

    func testRefreshDoesNothingWhenTheInstalledCopyIsAlreadyTheAppsVersion() async throws {
        let sandbox = try Sandbox()
        try await sandbox.install(version: "0.3.0")
        try sandbox.markInstalledCopy()
        let launchd = FakeRunner([Sandbox.launchctlPrint: ok("\tstate = running\n")])
        let bridge = sandbox.makeBridgeToRefresh(packaged: try sandbox.makeLoggingBridge(version: "0.3.0"), launchd: launchd)

        let outcome = await bridge.refreshAfterAppUpdate()

        XCTAssertEqual(outcome, .upToDate)
        XCTAssertTrue(try sandbox.installedCopyIsStillMarked(), "la copia no se vuelve a escribir")
        XCTAssertEqual(launchd.calls, [], "sin cambio de versión no se mira ni se toca launchd")
        XCTAssertEqual(sandbox.loggedCalls.filter { !$0.hasSuffix(":version") }, [])
    }

    func testRefreshReplacesTheCopyAndRestartsSyncWhenItWasLoaded() async throws {
        // Cargado en launchd, corra o no en este momento.
        for state in ["state = running", "state = not running"] {
            let sandbox = try Sandbox()
            try await sandbox.install(version: "0.3.0")
            let session = try sandbox.writeSessionAndHistory()
            let launchd = FakeRunner([Sandbox.launchctlPrint: ok("\t\(state)\n")])
            let bridge = sandbox.makeBridgeToRefresh(packaged: try sandbox.makeLoggingBridge(version: "0.4.0"), launchd: launchd)

            let outcome = await bridge.refreshAfterAppUpdate()

            XCTAssertEqual(outcome, .updated(sync: .restarted), state)
            let version = try await sandbox.run(sandbox.installed, "version")
            XCTAssertEqual(version, "0.4.0")
            // Lo reinicia la copia nueva, una sola vez, y es lo único que se le pide además de la versión.
            XCTAssertEqual(sandbox.loggedCalls.filter { !$0.hasSuffix(":version") }, ["0.4.0:install-launchd"], state)
            XCTAssertEqual(launchd.calls, [Sandbox.launchctlPrint], "a launchd solo se le pregunta")
            XCTAssertEqual(try sandbox.readSessionAndHistory(), session, "ni la sesión ni el historial se tocan")
        }
    }

    func testRefreshReplacesTheCopyButLeavesSyncAloneWhenItWasNotLoaded() async throws {
        let sandbox = try Sandbox()
        try await sandbox.install(version: "0.3.0")
        let launchd = FakeRunner([Sandbox.launchctlPrint: CommandResult(status: 113, output: "Could not find service")])
        let bridge = sandbox.makeBridgeToRefresh(packaged: try sandbox.makeLoggingBridge(version: "0.4.0"), launchd: launchd)

        let outcome = await bridge.refreshAfterAppUpdate()

        XCTAssertEqual(outcome, .updated(sync: .notLoaded))
        let version = try await sandbox.run(sandbox.installed, "version")
        XCTAssertEqual(version, "0.4.0")
        XCTAssertEqual(sandbox.loggedCalls.filter { !$0.hasSuffix(":version") }, [], "no se deja corriendo lo que nadie dejó corriendo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.state.appendingPathComponent("launchd").path))
    }

    func testRefreshKeepsTheInstalledCopyWhenTheAppBringsNoWorkingBridge() async throws {
        let sandbox = try Sandbox()
        try await sandbox.install(version: "0.3.0")
        try sandbox.markInstalledCopy()
        let launchd = FakeRunner([Sandbox.launchctlPrint: ok("\tstate = running\n")])
        let broken = sandbox.root.appendingPathComponent("no-contesta")
        try "#!/bin/sh\nexit 1\n".write(to: broken, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: broken.path)

        for packaged in [nil, broken] {
            let outcome = await sandbox.makeBridgeToRefresh(packaged: packaged, launchd: launchd).refreshAfterAppUpdate()

            XCTAssertEqual(outcome, .failed)
        }
        XCTAssertTrue(try sandbox.installedCopyIsStillMarked())
        XCTAssertEqual(launchd.calls, [])
    }

    func testRefreshRetriesTheRestartSoSyncIsNotLeftUnloaded() async throws {
        let sandbox = try Sandbox()
        try await sandbox.install(version: "0.3.0")
        try sandbox.failNextLaunchdInstalls(1)
        let launchd = FakeRunner([Sandbox.launchctlPrint: ok("\tstate = running\n")])
        let bridge = sandbox.makeBridgeToRefresh(packaged: try sandbox.makeLoggingBridge(version: "0.4.0"), launchd: launchd)

        let outcome = await bridge.refreshAfterAppUpdate()

        XCTAssertEqual(outcome, .updated(sync: .restarted))
        XCTAssertEqual(
            sandbox.loggedCalls.filter { !$0.hasSuffix(":version") }, ["0.4.0:install-launchd", "0.4.0:install-launchd"])
    }

    func testRefreshReportsARestartThatNeverWorked() async throws {
        let sandbox = try Sandbox()
        try await sandbox.install(version: "0.3.0")
        try sandbox.failNextLaunchdInstalls(99)
        let launchd = FakeRunner([Sandbox.launchctlPrint: ok("\tstate = running\n")])
        let bridge = sandbox.makeBridgeToRefresh(packaged: try sandbox.makeLoggingBridge(version: "0.4.0"), launchd: launchd)

        let outcome = await bridge.refreshAfterAppUpdate()

        XCTAssertEqual(outcome, .updated(sync: .failed), "la copia sí quedó al día; no lanza ni se cuelga")
        XCTAssertEqual(sandbox.loggedCalls.filter { $0.hasSuffix(":install-launchd") }.count, 3)
    }

    func testTheLaunchRefreshDoesNotRunWhenTheAppHostsTheTests() {
        XCTAssertFalse(WhatsAppBridge.refreshesAtLaunch(environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        XCTAssertTrue(WhatsAppBridge.refreshesAtLaunch(environment: ["HOME": "/Users/alguien"]))
    }

    // MARK: - Ayudas

    private func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    static func makePNG(seed: Int) -> Data {
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            NSColor.black.setFill()
            for row in 0..<8 {
                for column in 0..<8 where (row * 3 + column * 5 + seed * 7) % 3 == 0 {
                    NSRect(x: column * 8, y: row * 8, width: 8, height: 8).fill()
                }
            }
            return true
        }
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }
}

/// Una carpeta temporal con un "bridge" que es un script de shell: imprime lo que imprime el
/// de verdad y anota cada subcomando que le piden.
private final class Sandbox {
    let root: URL
    var state: URL { root.appendingPathComponent("state") }
    var installed: URL { root.appendingPathComponent("bin/galeno-whatsapp") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("galeno-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func makeBridge(version: String) throws -> URL {
        let url = root.appendingPathComponent("packaged-\(UUID().uuidString)")
        try "#!/bin/sh\n[ \"$1\" = version ] && echo \(version)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func makeWhatsAppBridge(pairSeconds: Int = 1) throws -> WhatsAppBridge {
        try WhatsAppBridgeTests.makePNG(seed: 1).write(to: state.appendingPathComponent("qr1.png"))
        try WhatsAppBridgeTests.makePNG(seed: 2).write(to: state.appendingPathComponent("qr2.png"))
        let script = """
            #!/bin/sh
            S="\(state.path)"
            echo "$@" >> "$S/calls.log"
            case "$1" in
              version) echo 0.2.0 ;;
              status)
                if [ -f "$S/linked" ]; then echo "Vinculado como 573001234567."; else echo "Sin vincular. Corre: galeno-whatsapp pair"; fi ;;
              pair)
                cp "$S/qr1.png" "$S/pair-qr.png"; sleep 0.4
                cp "$S/qr2.png" "$S/pair-qr.png"; sleep \(pairSeconds)
                rm -f "$S/pair-qr.png"; touch "$S/linked"; echo "Vinculado correctamente." ;;
              install-launchd) touch "$S/launchd"; echo "Listo: 'galeno-whatsapp sync' arrancará solo al iniciar sesión." ;;
              chats) echo '[{"jid":"1@g.us","name":"G","is_group":true},{"jid":"2@s.whatsapp.net","name":"B","is_group":false}]' ;;
              *) echo "subcomando desconocido" 1>&2; exit 1 ;;
            esac
            """
        let source = root.appendingPathComponent("packaged-bridge")
        try script.write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        return WhatsAppBridge(
            installer: BridgeInstaller(source: source, destination: installed),
            stateDirectory: state, pollInterval: .milliseconds(80), pairTimeout: 60)
    }

    // MARK: Para el refresco al arrancar

    /// Lo que `syncState()` le pregunta a launchd.
    static var launchctlPrint: String { "/bin/launchctl print gui/\(getuid())/com.galeno.whatsapp-bridge" }

    /// Un bridge de una versión dada que anota `<versión>:<subcomando>` cada vez que lo llaman. Solo sabe decir su
    /// versión e «instalar» el servicio; `launchd-fails` dice cuántas veces seguidas falla eso antes de funcionar.
    func makeLoggingBridge(version: String) throws -> URL {
        let script = """
            #!/bin/sh
            S="\(state.path)"
            echo "\(version):$1" >> "$S/refresh.log"
            case "$1" in
              version) echo \(version) ;;
              install-launchd)
                left=$(cat "$S/launchd-fails" 2>/dev/null || echo 0)
                if [ "$left" -gt 0 ]; then echo $((left - 1)) > "$S/launchd-fails"; echo "Bootstrap failed: 5" 1>&2; exit 1; fi
                touch "$S/launchd" ;;
              *) echo "subcomando desconocido" 1>&2; exit 1 ;;
            esac
            """
        let url = root.appendingPathComponent("packaged-\(version)-\(UUID().uuidString)")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Deja instalada la copia de una versión, como la dejó la app anterior, y olvida lo que se anotó al hacerlo.
    func install(version: String) async throws {
        try await BridgeInstaller(source: try makeLoggingBridge(version: version), destination: installed).ensureInstalled()
        try? FileManager.default.removeItem(at: state.appendingPathComponent("refresh.log"))
    }

    func makeBridgeToRefresh(packaged: URL?, launchd: FakeRunner) -> WhatsAppBridge {
        WhatsAppBridge(
            installer: BridgeInstaller(source: packaged, destination: installed), runner: launchd,
            stateDirectory: state, syncRestartRetryDelay: .milliseconds(10))
    }

    var loggedCalls: [String] {
        let log = (try? String(contentsOf: state.appendingPathComponent("refresh.log"), encoding: .utf8)) ?? ""
        return log.split(whereSeparator: \.isNewline).map(String.init)
    }

    func failNextLaunchdInstalls(_ count: Int) throws {
        try "\(count)\n".write(to: state.appendingPathComponent("launchd-fails"), atomically: true, encoding: .utf8)
    }

    // Una fecha imposible en la copia: si se vuelve a copiar, desaparece.
    func markInstalledCopy() throws {
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: installed.path)
    }

    func installedCopyIsStillMarked() throws -> Bool {
        let modified = try FileManager.default.attributesOfItem(atPath: installed.path)[.modificationDate] as? Date
        return modified == Date(timeIntervalSince1970: 0)
    }

    /// Los archivos que el bridge guarda en su carpeta (`cli.go`): la sesión y el historial.
    func writeSessionAndHistory() throws -> [Data] {
        try Data("sesion".utf8).write(to: state.appendingPathComponent("whatsmeow.db"))
        try Data("historial".utf8).write(to: state.appendingPathComponent("messages.db"))
        return try readSessionAndHistory()
    }

    func readSessionAndHistory() throws -> [Data] {
        try ["whatsmeow.db", "messages.db"].map { try Data(contentsOf: state.appendingPathComponent($0)) }
    }

    func run(_ executable: URL, _ argument: String) async throws -> String {
        let result = await ProcessRunner().run(executable.path, arguments: [argument], timeout: 10)
        return (result?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
