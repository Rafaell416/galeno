import Foundation

/// Las sesiones de Code que la app de Claude guarda en su carpeta de datos, solo para saber **cuál fue la
/// última de una carpeta** y poder volver a ella en vez de abrir una nueva.
///
/// Es una carpeta de otra app, no un contrato: se lee en solo lectura, y solo cuatro campos (`sessionId`, `cwd`,
/// `isArchived`, `lastActivityAt`); nunca el título ni nada de la conversación. Si el formato cambia o no hay
/// nada, devuelve `nil` y quien llama abre una sesión nueva como antes.
nonisolated struct ClaudeSessionStore: Sendable {
    var root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)

    /// La forma que la app acepta en su enlace `claude://code/continue?session=…`.
    static let idPattern = #"^local_[A-Za-z0-9-]{1,64}$"#

    private struct Entry: Decodable {
        var sessionId: String
        var cwd: String
        var isArchived: Bool?
        var lastActivityAt: Double?
    }

    /// La sesión no archivada de esa carpeta con actividad más reciente.
    func latestSessionID(in folder: URL) -> String? {
        let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
        guard let level1 = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return nil }
        var best: (id: String, at: Double)?
        for dir1 in level1 {
            guard let level2 = try? FileManager.default.contentsOfDirectory(at: dir1, includingPropertiesForKeys: nil)
            else { continue }
            for dir2 in level2 {
                guard let files = try? FileManager.default.contentsOfDirectory(at: dir2, includingPropertiesForKeys: nil)
                else { continue }
                for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    guard let data = try? Data(contentsOf: file),
                        let entry = try? JSONDecoder().decode(Entry.self, from: data),
                        entry.isArchived != true,
                        entry.sessionId.range(of: Self.idPattern, options: .regularExpression) != nil,
                        URL(fileURLWithPath: entry.cwd).standardizedFileURL.resolvingSymlinksInPath().path == path
                    else { continue }
                    let at = entry.lastActivityAt ?? 0
                    if best == nil || at > best!.at { best = (entry.sessionId, at) }
                }
            }
        }
        return best?.id
    }
}
