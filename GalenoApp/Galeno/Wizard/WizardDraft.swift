import Foundation
import GalenoCore

/// El asistente a medias (B1 · «Reanudar donde quedaste»): lo que el usuario ya eligió, para no
/// empezar de cero si cierra la app en el paso 5. **Sin credenciales**: los tokens viven en
/// Claude Code, y aquí solo hay lo mismo que lleva un `AgentConfig` (nombres, herramientas, skills,
/// reglas, el `client_id` público). Se borra al terminar.
struct WizardDraft: Codable, Equatable {
    /// La 2 es la del asistente de seis pasos: un borrador de la 1 (diez pasos, sin rol) se ignora.
    static let currentVersion = 3

    var version = WizardDraft.currentVersion
    var step: Int
    var furthestStep: Int
    var language: Language
    var role: AgentRole = .productManager
    var agentName: String
    var projectDescription: String
    var connections: [ToolConnection]
    var skills: [SelectedSkill]
    var skillsInitialized: Bool
    var sendingRules: SendingRules
}

/// Dónde se guarda el borrador. Las pruebas usan uno en memoria: ninguna toca el disco real.
@MainActor
protocol DraftStoring: AnyObject {
    func load() -> WizardDraft?
    func save(_ draft: WizardDraft)
    func clear()
}

/// `~/Library/Application Support/Galeno/draft.json`, legible solo por el usuario.
@MainActor
final class FileDraftStore: DraftStoring {
    private let url: URL

    init(url: URL = FileDraftStore.defaultURL) { self.url = url }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Galeno/draft.json")
    }

    func load() -> WizardDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Un borrador ilegible o de otra versión se ignora: no vale la pena fallar por él.
        guard let draft = try? JSONDecoder().decode(WizardDraft.self, from: data), draft.version == WizardDraft.currentVersion else {
            return nil
        }
        return draft
    }

    func save(_ draft: WizardDraft) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(draft)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Perder el borrador no rompe nada: el asistente sigue funcionando.
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
final class MemoryDraftStore: DraftStoring {
    private(set) var draft: WizardDraft?
    init(_ draft: WizardDraft? = nil) { self.draft = draft }
    func load() -> WizardDraft? { draft }
    func save(_ draft: WizardDraft) { self.draft = draft }
    func clear() { draft = nil }
}
