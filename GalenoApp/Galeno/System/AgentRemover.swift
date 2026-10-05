import Foundation
import GalenoCore

/// Lo que se va a mandar a la Papelera al eliminar un agente, calculado **antes** para enseñárselo al usuario.
nonisolated struct AgentRemovalPlan: Equatable, Sendable {
    /// La carpeta del agente (con su `memoria/`). `nil` si ya no existe, o si no está dentro de la carpeta de
    /// agentes de Galeno: una ruta rara en `installation.json` nunca nos lleva a borrar otra cosa.
    var folder: URL?
    /// Lo que Claude Code guardó de esa carpeta: sus conversaciones y sus notas (`~/.claude/projects/<carpeta>`).
    var claudeCodeData: URL?
    /// Las conversaciones de la app de Claude (escritorio) en esa carpeta.
    var desktopSessions: [URL]
    /// Cuántas conversaciones hay en total (las de Claude Code; la app de Claude guarda las suyas aparte).
    var conversationCount: Int

    var isEmpty: Bool { folder == nil && claudeCodeData == nil && desktopSessions.isEmpty }
}

/// Elimina un agente: su carpeta y lo que Claude Code y la app de Claude guardaron de ella, **a la Papelera**
/// (recuperable; nunca se borra nada para siempre).
///
/// Solo toca lo que es de ese agente, y por rutas exactas: la carpeta (si está dentro de `agentsRoot`), la carpeta de
/// proyecto de Claude Code que corresponde a esa ruta, y las sesiones de la app de Claude cuyo `cwd` es esa carpeta.
/// **No** toca `~/.claude.json` (ahí Claude Code guarda ajustes de todos tus proyectos), ni las conexiones, ni la
/// sesión de WhatsApp, ni la app de Slack.
nonisolated struct AgentRemover: Sendable {
    var agentsRoot: URL = AgentFolder.defaultRoot
    var claudeProjects: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)
    var desktopSessions = ClaudeSessionStore()
    /// Mueve a la Papelera. Las pruebas lo reemplazan.
    var trash: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Cómo nombra Claude Code la carpeta de proyecto de una ruta: todo lo que no es letra o cifra ASCII, un `-`
    /// (`/Users/rafa/Galeno/TESTING 2` → `-Users-rafa-Galeno-TESTING-2`, comprobado con sus carpetas reales).
    static func projectFolderName(for folder: URL) -> String {
        projectFolderName(forPath: folder.path)
    }

    static func projectFolderName(forPath path: String) -> String {
        String(path.unicodeScalars.map { scalar in
            ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
                ? Character(scalar) : "-"
        })
    }

    /// Las dos formas en que una ruta con acentos puede haberse escrito (`ó` suelta o `o` + acento): Claude Code
    /// nombra la carpeta con la que le llegó, y no sabemos cuál. Sin acentos es una sola.
    static func projectFolderNames(for folder: URL) -> [String] {
        var seen: [String] = []
        for path in [folder.path, folder.path.precomposedStringWithCanonicalMapping, folder.path.decomposedStringWithCanonicalMapping] {
            let name = projectFolderName(forPath: path)
            if !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    func plan(for record: AgentRecord) -> AgentRemovalPlan {
        let fileManager = FileManager.default
        let folder = record.folder.standardizedFileURL

        // La carpeta: tiene que existir, ser una carpeta de verdad (no un enlace) y estar dentro de ~/Galeno.
        var folderToTrash: URL?
        let root = agentsRoot.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        let values = try? folder.resourceValues(forKeys: [.isSymbolicLinkKey])
        if folder.path.hasPrefix(root + "/"), folder.path != root,
            fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
            values?.isSymbolicLink != true
        {
            folderToTrash = folder
        }

        // Lo de Claude Code: la carpeta de proyecto de esa ruta, directamente dentro de `~/.claude/projects`.
        var project: URL?
        var conversations = 0
        for name in Self.projectFolderNames(for: folder) {
            let candidate = claudeProjects.appendingPathComponent(name, isDirectory: true)
            let values = try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard candidate.deletingLastPathComponent().standardizedFileURL == claudeProjects.standardizedFileURL,
                values?.isDirectory == true, values?.isSymbolicLink != true
            else { continue }
            project = candidate
            conversations =
                ((try? fileManager.contentsOfDirectory(atPath: candidate.path)) ?? [])
                .filter { $0.hasSuffix(".jsonl") }.count
            break
        }

        return AgentRemovalPlan(
            folder: folderToTrash, claudeCodeData: project,
            desktopSessions: desktopSessions.sessionFiles(in: folder), conversationCount: conversations)
    }

    struct Outcome: Equatable, Sendable {
        /// Lo que no se pudo mandar a la Papelera, para decírselo al usuario.
        var failed: [URL]
    }

    /// Manda el plan a la Papelera. **Si falla la carpeta del agente, no sigue**: sin ella no hay agente que quitar.
    /// Lo de Claude Code y la app de Claude se intenta aunque algo falle, y lo que no se pudo se devuelve.
    func execute(_ plan: AgentRemovalPlan) throws -> Outcome {
        if let folder = plan.folder { try trash(folder) }
        var failed: [URL] = []
        for url in [plan.claudeCodeData].compactMap({ $0 }) + plan.desktopSessions {
            do { try trash(url) } catch { failed.append(url) }
        }
        return Outcome(failed: failed)
    }
}
