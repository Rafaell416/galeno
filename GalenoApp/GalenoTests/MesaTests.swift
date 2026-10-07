import GalenoCore
import XCTest

@testable import Galeno

/// La mesa del home (`docs/03` §3b): a quién le toca cada sitio, que todo cabe en el lienzo, y que un personaje
/// solo «trabaja» si su agente tuvo actividad hace poco. Todo en carpetas temporales.
@MainActor
final class MesaTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("galeno-mesa-\(UUID().uuidString)", isDirectory: true)
        suiteName = "galeno-mesa-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// Un home con estos agentes (nombre, rol). Devuelve también la carpeta de cada uno, por su nombre.
    private func makeModel(
        _ agents: [(String, AgentRole)], withoutFolder: Set<String> = [], activity: @escaping @Sendable ([String: URL]) -> [String: Date] = { _ in [:] }
    ) throws -> HomeModel {
        let store = InstallationStore(directory: root.appendingPathComponent("support"))
        var installation = GalenoInstallation(language: .spanish)
        var folders: [String: URL] = [:]
        for (name, role) in agents {
            let config = AgentConfig(agentName: name, language: .spanish, role: role, projectDescription: "Proyecto de \(name)")
            let record = installation.addAgent(config, agentsRoot: root.appendingPathComponent("Galeno"))
            if !withoutFolder.contains(name) {
                try FileManager.default.createDirectory(at: record.folder, withIntermediateDirectories: true)
            }
            folders[name] = record.folder
        }
        try store.save(installation)
        let known = folders
        return HomeModel(
            store: store, defaults: defaults, opener: ScriptedOpener(), claudePath: "/ruta/claude", settle: {},
            activityReader: { activity(known) })
    }

    // MARK: - Los personajes

    func testEveryRoleHasItsOwnCharacter() {
        XCTAssertEqual(AgentRole.productManager.persona.name, "Galeno")
        XCTAssertEqual(AgentRole.marketing.persona.name, "Wedgwood")
        XCTAssertEqual(AgentRole.sales.persona.name, "Marco")
        XCTAssertEqual(Set(AgentRole.allCases.map(\.persona.portrait)).count, AgentRole.allCases.count)
        XCTAssertEqual(Set(AgentRole.allCases.map(\.persona.figure)).count, AgentRole.allCases.count)
    }

    func testTheHomeKnowsTheRoleOfEachAgent() throws {
        let model = try makeModel([("Hera", .marketing), ("Atlas", .sales)])
        XCTAssertEqual(model.agents.map(\.role), [.marketing, .sales])
    }

    // MARK: - Los sitios

    /// Seis por mesa, del centro hacia los extremos; nadie cambia de sitio cuando llega otro.
    func testSeatsFillFromTheMiddleAndNobodyMoves() throws {
        let three = try makeModel([("A", .productManager), ("B", .marketing), ("C", .sales)])
        let seats = Mesa.tables(for: three.agents)
        XCTAssertEqual(seats.count, 1)
        XCTAssertEqual(seats[0].map(\.position), [2, 3, 1])
        XCTAssertEqual(seats[0].map(\.agent.name), ["A", "B", "C"])

        XCTAssertEqual(Set(Mesa.fillOrder), Set(0..<Mesa.seatsPerTable), "cada sitio se ocupa una vez")
    }

    /// El séptimo agente se sienta solo en una segunda mesa.
    func testTheSeventhAgentSitsAtASecondTable() throws {
        let model = try makeModel((1...7).map { ("Agente \($0)", .productManager) })
        let tables = Mesa.tables(for: model.agents)
        XCTAssertEqual(tables.map(\.count), [6, 1])
        XCTAssertEqual(Set(tables[0].map(\.position)), Set(0..<6))
        XCTAssertEqual(tables[1].first?.agent.name, "Agente 7")
        XCTAssertEqual(tables[1].first?.position, Mesa.fillOrder[0])
        XCTAssertTrue(Mesa.tables(for: []).isEmpty)
    }

    /// Dos agentes del mismo rol son el mismo personaje: el segundo se distingue (mira al otro lado).
    func testASecondAgentOfTheSameRoleLooksDifferent() throws {
        let model = try makeModel([("A", .productManager), ("B", .marketing), ("C", .productManager), ("D", .productManager)])
        XCTAssertEqual(Mesa.tables(for: model.agents)[0].map(\.alternate), [false, false, true, false])
    }

    /// La ventana es fija: figuras, nombres y lo que responde al clic caben en el lienzo, y la mesa no tiene fuga.
    func testEverySeatFitsInsideTheCanvas() {
        let canvas = CGRect(origin: .zero, size: Mesa.size)
        for position in 0..<Mesa.seatsPerTable {
            XCTAssertTrue(canvas.contains(Mesa.hitRect(position)), "sitio \(position)")
            XCTAssertTrue(canvas.insetBy(dx: 54, dy: 8).contains(Mesa.labelAnchor(position)), "nombre \(position)")
            XCTAssertTrue((0.06...0.94).contains(Mesa.along(position)))
            // Las láminas de los tres personajes también: la figura, su nombre y su mano dentro de la imagen.
            for role in AgentRole.allCases {
                let plate = role.persona.plate
                let rise = plate.height - Mesa.plateSink
                XCTAssertTrue(canvas.contains(Mesa.plateRect(position, aspect: plate.aspect, height: plate.height)), "\(role) en \(position)")
                XCTAssertTrue(canvas.contains(Mesa.hitRect(position, rise: rise)))
                XCTAssertTrue(canvas.insetBy(dx: 54, dy: 8).contains(Mesa.labelAnchor(position, rise: rise)))
                XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(plate.hand))
            }
        }
        // Un paralelogramo: los dos extremos del tablero miden lo mismo y las figuras no encogen con la distancia.
        XCTAssertEqual(Mesa.frontNear.x - Mesa.backNear.x, Mesa.frontFar.x - Mesa.backFar.x, accuracy: 0.01)
        XCTAssertEqual(Mesa.frontNear.y - Mesa.backNear.y, Mesa.frontFar.y - Mesa.backFar.y, accuracy: 0.01)
        XCTAssertEqual(Mesa.scale(0), Mesa.scale(5))
        for corner in [Mesa.backNear, Mesa.backFar, Mesa.frontFar, Mesa.frontNear] {
            XCTAssertTrue(canvas.contains(corner))
        }
        XCTAssertLessThanOrEqual(Mesa.size.width, WindowMetrics.width - 2 * Space.s48)
    }

    /// La mano que escribe se mueve poco: nunca se sale de su papel.
    func testTheWritingHandStaysOnItsPaper() {
        for step in 0..<400 {
            let offset = Mesa.writingOffset(time: Double(step) * 0.037, position: step % 6)
            XCTAssertLessThanOrEqual(abs(offset.width), 7.01)
            XCTAssertLessThanOrEqual(abs(offset.height), 4.5)
        }
    }

    // MARK: - Trabajando de verdad

    /// Solo se mueve quien trabajó hace poco: sin actividad conocida, nadie; con una vieja, tampoco.
    func testOnlyAnAgentWithRecentActivityIsWorking() async throws {
        let now = Date()
        let model = try makeModel([("Hera", .productManager), ("Atlas", .sales), ("Iris", .marketing)]) { folders in
            [
                ClaudeSessionStore.resolved(folders["Hera"]!): now.addingTimeInterval(-30),
                ClaudeSessionStore.resolved(folders["Atlas"]!): now.addingTimeInterval(-3600),
            ]
        }
        XCTAssertFalse(model.agents.contains { model.isWorking($0, now: now) }, "antes de mirar, nadie trabaja")

        await model.refreshActivity()
        XCTAssertEqual(model.agents.filter { model.isWorking($0, now: now) }.map(\.name), ["Hera"])
        // Pasada la ventana, deja de escribir aunque nadie vuelva a mirar.
        let later = now.addingTimeInterval(HomeModel.workingWindow + 60)
        XCTAssertFalse(model.agents.contains { model.isWorking($0, now: later) })
    }

    /// Un agente sin carpeta no trabaja, diga lo que diga la app de Claude.
    func testAnAgentWithoutItsFolderIsNeverWorking() async throws {
        let now = Date()
        let model = try makeModel([("Hera", .productManager)], withoutFolder: ["Hera"]) { folders in
            [ClaudeSessionStore.resolved(folders["Hera"]!): now]
        }
        await model.refreshActivity()
        XCTAssertFalse(model.isWorking(model.agents[0], now: now))
    }

    /// El menú del clic derecho: se abre sobre un agente con carpeta y se cierra al elegir; sin carpeta no hay menú.
    func testTheSeatMenuOpensOnlyForAnAgentWithItsFolder() throws {
        let model = try makeModel([("Hera", .productManager), ("Atlas", .sales)], withoutFolder: ["Atlas"])
        model.showMenu(model.agents[1])
        XCTAssertNil(model.menuOpen, "sin carpeta no hay nada que abrir ni gestionar")

        model.showMenu(model.agents[0])
        XCTAssertEqual(model.menuOpen, model.agents[0].id)
        model.closeMenu()
        XCTAssertNil(model.menuOpen)
    }

    /// La mesa es como se ve el home de fábrica; las tarjetas siguen a un interruptor.
    func testTheTableIsTheDefaultLayout() {
        XCTAssertEqual(HomeLayout(rawValue: defaults.string(forKey: Prefs.homeLayout) ?? "") ?? .table, .table)
        XCTAssertEqual(HomeLayout.allCases, [.table, .cards])
    }
}
