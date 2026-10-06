import Foundation
import GalenoCore
import UniformTypeIdentifiers

/// Una skill propia en el asistente: lo que dice de sí misma y, si todavía no está en la carpeta del agente, de
/// dónde copiarla al crear o guardar.
struct OwnSkillEntry: Identifiable, Equatable, Sendable {
    var skill: OwnSkill
    /// De dónde se copia al guardar. `nil` = ya está en `skills-propias/` del agente.
    var pendingSource: URL?

    var id: String { skill.id }
}

/// Trae una skill propia del Mac del usuario a `skills-propias/<id>/` de su agente (`docs/03` §6.3; decisión de
/// Rafa, 6 oct 2026). Solo archivos locales que el usuario eligió en el selector: nada remoto, nada se descarga,
/// nada se ejecuta, y el original no se toca. Lo que se quita va a la Papelera, nunca se borra.
nonisolated enum OwnSkillImporter {
    enum Failure: Error, Equatable {
        /// Una carpeta sin `SKILL.md`, o un archivo que no es Markdown.
        case noSkillFile
        /// Del nombre no sale un id válido (`OwnSkills.identifier`).
        case invalidName
        case unreadable
    }

    /// Lo que acepta el selector: una carpeta o un archivo Markdown.
    static var allowedTypes: [UTType] {
        [.folder, .plainText]
            + [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown")].compactMap { $0 }
    }

    /// Un `SKILL.md` más grande que esto no es una skill.
    static let maxFileBytes = 1_000_000

    /// Mira lo elegido sin copiar nada: una carpeta con `SKILL.md`, o un `.md` suelto que será el `SKILL.md`.
    static func inspect(_ url: URL) throws -> OwnSkill {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let id = OwnSkills.identifier(from: url.lastPathComponent)
        guard !id.isEmpty, (try? OwnSkills.validate(id)) != nil else { throw Failure.invalidName }
        let file = try skillFile(in: url)
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileBytes else { throw Failure.unreadable }
        guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else {
            throw Failure.unreadable
        }
        return OwnSkills.describe(id: id, skillText: text)
    }

    /// Copia la carpeta (entera: una skill puede traer plantillas al lado) o el archivo, como
    /// `skills-propias/<id>/SKILL.md`. Si ya había una copia con ese id, la anterior va a la Papelera.
    static func copy(_ url: URL, id: String, into agentFolder: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        try OwnSkills.validate(id)
        let fileManager = FileManager.default
        let root = OwnSkills.directory(in: agentFolder)
        let target = root.appending(path: id, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.trashItem(at: target, resultingItemURL: nil)
        }
        if isDirectory(url) {
            try fileManager.copyItem(at: url, to: target)
        } else {
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            try fileManager.copyItem(at: url, to: target.appending(path: OwnSkills.skillFileName))
        }
    }

    /// Manda `skills-propias/<id>/` a la Papelera. Nada si no existe.
    static func trash(id: String, in agentFolder: URL) throws {
        try OwnSkills.validate(id)
        let target = OwnSkills.directory(in: agentFolder).appending(path: id, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.trashItem(at: target, resultingItemURL: nil)
    }

    private static func skillFile(in url: URL) throws -> URL {
        if isDirectory(url) {
            let file = url.appending(path: OwnSkills.skillFileName)
            guard FileManager.default.fileExists(atPath: file.path) else { throw Failure.noSkillFile }
            return file
        }
        guard ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) else { throw Failure.noSkillFile }
        return url
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
