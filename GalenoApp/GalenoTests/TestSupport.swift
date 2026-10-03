import Foundation
import XCTest

@testable import Galeno

/// Un `CommandRunning` con respuestas fijas, para probar sin lanzar nada. La clave es
/// el comando entero: "/ruta/claude --version". Sin respuesta registrada devuelve
/// `nil`, como un comando que no terminó a tiempo.
final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let responses: [String: CommandResult]
    private let lock = NSLock()
    private var recorded: [String] = []

    init(_ responses: [String: CommandResult]) { self.responses = responses }

    var calls: [String] { lock.withLock { recorded } }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult? {
        let command = ([executable] + arguments).joined(separator: " ")
        lock.withLock { recorded.append(command) }
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
