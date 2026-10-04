import Foundation
import GalenoCore
import XCTest

@testable import Galeno

/// Un `CommandRunning` con respuestas fijas, para probar sin lanzar nada. La clave es
/// el comando entero: "/ruta/claude --version". Sin respuesta registrada devuelve
/// `nil`, como un comando que no terminó a tiempo.
final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let responses: [String: CommandResult]
    private let lock = NSLock()
    private var recorded: [String] = []
    private var recordedEnvironments: [[String: String]] = []

    init(_ responses: [String: CommandResult]) { self.responses = responses }

    var calls: [String] { lock.withLock { recorded } }
    /// El entorno que se pidió añadir en cada llamada, en orden.
    var environments: [[String: String]] { lock.withLock { recordedEnvironments } }

    func run(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> CommandResult? {
        let command = ([executable] + arguments).joined(separator: " ")
        lock.withLock {
            recorded.append(command)
            recordedEnvironments.append(environment)
        }
        return responses[command]
    }
}

func ok(_ output: String) -> CommandResult { CommandResult(status: 0, output: output) }

/// Espera (con tiempo máximo) a que algo pase, cediendo el hilo para que corran las tareas.
@MainActor
func waitUntil(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Un reloj que no espera: anota lo que se le pidió dormir y sigue. Las duraciones de
/// `stalling` sí se detienen (hasta que se cancele la tarea), para poder **ver** una
/// pantalla antes de que el flujo la deje atrás.
final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []
    private let stalling: Set<Duration>

    init(stalling: Set<Duration> = []) { self.stalling = stalling }

    var durations: [Duration] { lock.withLock { recorded } }
    var seconds: Double {
        durations.reduce(0) { $0 + Double($1.components.seconds) + Double($1.components.attoseconds) / 1e18 }
    }

    var sleeper: @Sendable (Duration) async -> Void {
        { [self] duration in
            lock.withLock { recorded.append(duration) }
            if stalling.contains(duration) {
                _ = try? await Task.sleep(for: .seconds(30))
            } else {
                await Task.yield()
            }
        }
    }

    /// Detiene el éxito de 1,5 s: la pantalla de éxito se queda hasta que algo la avance.
    static var holdingSuccess: SleepLog { SleepLog(stalling: [.milliseconds(1500)]) }
}

/// Lee un archivo del repo sin colgarse.
///
/// El repo suele vivir en `~/Documents`, y macOS puede pedir permiso para que la app de pruebas
/// lea esa carpeta: mientras nadie responde, la lectura se queda bloqueada (llegó a parar una
/// corrida 6 minutos). Si no responde a tiempo, la prueba **se salta** con un aviso, no se
/// cuelga. En CI el repo no está en una carpeta protegida y siempre se lee.
func readRepoFile(_ url: URL, timeout: TimeInterval = 5) throws -> Data {
    final class Box: @unchecked Sendable { var result: Result<Data, any Error>? }
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .userInitiated).async {
        box.result = Result { try Data(contentsOf: url) }
        done.signal()
    }
    guard done.wait(timeout: .now() + timeout) == .success, let result = box.result else {
        throw XCTSkip("No se pudo leer \(url.lastPathComponent) a tiempo: macOS puede estar pidiendo permiso para la carpeta del repo.")
    }
    return try result.get()
}

extension AgentInstaller {
    /// Un instalador que escribe en una carpeta temporal: ninguna prueba toca el `~/Galeno` ni el
    /// `installation.json` reales. `skills`: la carpeta con las skills de la prueba.
    static func sandboxed(skills: URL? = nil) -> AgentInstaller {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeno-test-\(UUID().uuidString)", isDirectory: true)
        return AgentInstaller(
            store: InstallationStore(directory: sandbox.appendingPathComponent("support")),
            agentsRoot: sandbox.appendingPathComponent("Galeno"),
            options: ConfigGenerator.Options(
                skillsDirectory: skills ?? sandbox.appendingPathComponent("skills"),
                whatsAppBridgePath: "/bridge/galeno-whatsapp"))
    }
}
