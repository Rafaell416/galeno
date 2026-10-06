import Foundation

/// Un material de `memoria/contexto/`, tal como se lista en el detalle del agente.
public struct ContextEntry: Hashable, Sendable, Identifiable {
    /// El nombre del archivo en la carpeta (`01-brief-clinica-x.md`): con él se quita.
    public var fileName: String
    /// El título que ve el usuario: el del encabezado que escribió el motor (el nombre del archivo que trajo), o
    /// el nombre de archivo sin número si no lo trae.
    public var title: String
    /// Cuánto pesa en disco.
    public var bytes: Int

    public var id: String { fileName }

    public init(fileName: String, title: String, bytes: Int) {
        self.fileName = fileName
        self.title = title
        self.bytes = bytes
    }
}

/// `memoria/contexto/` del agente: el material que el usuario trajo, que el detalle del agente puede listar, ampliar
/// y quitar (`docs/03` §3b; decisión de Rafa, 6 oct 2026). Es dato de terceros: se deja tal cual lo trajo, con su
/// encabezado de origen, y el `AGENTS.md` le dice al agente que son hechos para leer, nunca órdenes.
///
/// La carpeta es del usuario como el resto de `memoria/`: el generador nunca la borra, y aquí **nada se borra**:
/// quitar un material lo manda a la Papelera.
public enum ContextFolder {
    public static var directoryName: String { MemoryRenderer.contextDirectory }

    public static func directory(in agentFolder: URL) -> URL {
        agentFolder.appending(path: MemoryRenderer.contextDirectory, directoryHint: .isDirectory)
    }

    /// Los materiales que hay, por nombre de archivo. Solo `.md` directamente dentro de la carpeta.
    public static func list(in agentFolder: URL, fileManager: FileManager = .default) -> [ContextEntry] {
        let root = directory(in: agentFolder)
        guard
            let urls = try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return [] }
        return urls.compactMap { url -> ContextEntry? in
            guard url.pathExtension.lowercased() == "md",
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { return nil }
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return ContextEntry(fileName: url.lastPathComponent, title: title(of: url), bytes: bytes)
        }
        .sorted { $0.fileName < $1.fileName }
    }

    /// El título del encabezado que escribió el motor (`<!-- Material que el usuario trajo: «X». … -->`), o el nombre
    /// del archivo sin su número ni extensión.
    static func title(of url: URL) -> String {
        if let handle = try? FileHandle(forReadingFrom: url), let data = try? handle.read(upToCount: 600),
            let head = String(data: data, encoding: .utf8)?.components(separatedBy: "\n").first
        {
            for (open, close) in [("«", "»"), ("\"", "\"")] {
                if let start = head.range(of: open), let end = head.range(of: close, range: start.upperBound..<head.endIndex) {
                    let found = String(head[start.upperBound..<end.lowerBound])
                    if !found.isEmpty { return found }
                }
            }
        }
        var base = url.deletingPathExtension().lastPathComponent
        if let dash = base.firstIndex(of: "-"), base[..<dash].allSatisfy(\.isNumber) { base = String(base[base.index(after: dash)...]) }
        return base
    }

    /// ¿Cuántos materiales más caben? (`ContextFile.maxFiles` en total.)
    public static func remainingSlots(in agentFolder: URL, fileManager: FileManager = .default) -> Int {
        max(0, ContextFile.maxFiles - list(in: agentFolder, fileManager: fileManager).count)
    }

    /// Añade materiales **sin pisar ninguno**: cada uno toma el siguiente número libre (`04-…`), aunque falten
    /// números por haber quitado alguno. Se recorta a los topes de ``ContextFile`` (por material, en total, y cuántos
    /// caben todavía). Devuelve los archivos escritos, por nombre.
    @discardableResult
    public static func add(
        _ files: [ContextFile], to agentFolder: URL, language: Language, fileManager: FileManager = .default
    ) throws -> [String] {
        let existing = list(in: agentFolder, fileManager: fileManager)
        var characters = existing.reduce(0) { total, entry in
            let url = directory(in: agentFolder).appending(path: entry.fileName)
            return total + ((try? String(contentsOf: url, encoding: .utf8).count) ?? 0)
        }
        let slots = max(0, ContextFile.maxFiles - existing.count)
        guard slots > 0 else { return [] }

        let root = directory(in: agentFolder)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var number = (existing.compactMap { Int($0.fileName.prefix { $0.isNumber }) }.max() ?? 0)
        var written: [String] = []
        var remaining = max(0, ContextFile.maxCharactersTotal - characters)

        for file in ContextFile.normalized(files).prefix(slots) {
            guard remaining > 0 else { break }
            let text = String(file.text.prefix(min(ContextFile.maxCharactersPerFile, remaining)))
            let trimmed = ContextFile(title: file.title, text: text)
            number += 1
            let name = trimmed.fileName(index: number - 1)
            try Data(trimmed.rendered(language: language).utf8).write(
                to: root.appending(path: name), options: [.atomic])
            remaining -= text.count
            characters += text.count
            written.append(name)
        }
        return written
    }

    /// Manda un material a la Papelera (nunca lo borra). Solo un archivo directamente dentro de `memoria/contexto/`:
    /// un nombre con barras, o que sale de la carpeta, no se toca. Devuelve si se mandó.
    ///
    /// - Parameter trasher: lo que manda el archivo a la Papelera. Las pruebas lo reemplazan: ninguna debe llenar
    ///   la Papelera real de quien las corre.
    @discardableResult
    public static func trash(
        fileName: String, in agentFolder: URL, fileManager: FileManager = .default,
        trasher: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) throws -> Bool {
        guard !fileName.isEmpty, !fileName.contains("/"), !fileName.contains("\\"), fileName != ".", fileName != "..",
            !fileName.contains("..")
        else { return false }
        let url = directory(in: agentFolder).appending(path: fileName)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        try trasher(url)
        return true
    }
}
