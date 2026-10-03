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

    func run(_ executable: URL, _ argument: String) async throws -> String {
        let result = await ProcessRunner().run(executable.path, arguments: [argument], timeout: 10)
        return (result?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
