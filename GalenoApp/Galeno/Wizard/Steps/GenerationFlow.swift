import Combine
import Foundation
import GalenoCore

/// La pantalla 9: "construyendo tu agente". El motor escribe la carpeta de una vez (son
/// milisegundos); los pasos visibles le ponen nombre a lo que escribe y le dan a la espera el
/// ritmo de una experiencia, sin inventar nada: si el motor falla, se para ahí y lo dice.
@MainActor
final class GenerationFlow: ObservableObject {
    enum Step: CaseIterable, Equatable {
        case rules
        case tools
        case skills
        case saving
    }

    enum Phase: Equatable {
        case running
        case succeeded
        case failed(String)
    }

    typealias Sleeper = @Sendable (Duration) async -> Void

    @Published private(set) var phase: Phase = .running
    /// El paso que se está escribiendo.
    @Published private(set) var current: Step?
    @Published private(set) var completed: Set<Step> = []
    @Published private(set) var outcome: AgentInstaller.Outcome?

    /// Lo que se ve cada paso como mínimo.
    var stepDuration: Duration = .milliseconds(700)

    private let install: @Sendable () throws -> AgentInstaller.Outcome
    private let sleep: Sleeper
    private var task: Task<Void, Never>?

    init(
        sleep: @escaping Sleeper = { _ = try? await Task.sleep(for: $0) },
        install: @escaping @Sendable () throws -> AgentInstaller.Outcome
    ) {
        self.sleep = sleep
        self.install = install
    }

    /// Empieza a escribir. Si ya terminó o está en marcha, no hace nada.
    func start() {
        guard task == nil else { return }
        phase = .running
        let install = self.install
        let box = ResultBox()

        // El trabajo real, fuera del hilo principal.
        Task.detached(priority: .userInitiated) {
            box.set(Result { try install() })
        }

        task = Task { [weak self] in
            guard let self else { return }
            for step in Step.allCases {
                self.current = step
                var waited = Duration.zero
                // Un paso se ve al menos `stepDuration`; si el motor falló, no se espera.
                while waited < self.stepDuration {
                    if case .failure? = box.value { break }
                    await self.sleep(.milliseconds(50))
                    waited += .milliseconds(50)
                    if Task.isCancelled { return }
                }
                if case .failure? = box.value { break }
                self.completed.insert(step)
            }
            // El último paso no termina hasta que el motor entregó su resultado.
            while box.value == nil {
                await self.sleep(.milliseconds(25))
                if Task.isCancelled { return }
            }
            switch box.value! {
            case .success(let outcome):
                self.outcome = outcome
                self.current = nil
                self.phase = .succeeded
            case .failure(let error):
                self.phase = .failed(Self.describe(error))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Vuelve a intentar tras un fallo.
    func retry() {
        guard case .failed = phase else { return }
        task = nil
        current = nil
        completed = []
        start()
    }

    /// Los errores del motor se explican solos; los del sistema (escribir un archivo, permisos)
    /// se leen mejor por su descripción localizada.
    static func describe(_ error: any Error) -> String {
        if error is CocoaError || error is URLError || error is POSIXError || type(of: error) is NSError.Type {
            return error.localizedDescription
        }
        return String(describing: error)
    }
}

/// El resultado del trabajo real, compartido entre el hilo que lo hace y el que anima.
private nonisolated final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<AgentInstaller.Outcome, any Error>?

    var value: Result<AgentInstaller.Outcome, any Error>? { lock.withLock { stored } }
    func set(_ result: Result<AgentInstaller.Outcome, any Error>) { lock.withLock { stored = result } }
}
