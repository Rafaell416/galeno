import Foundation
import GalenoCore
import PDFKit
import UniformTypeIdentifiers

/// Lee un archivo que el usuario trae como contexto de su proyecto y lo vuelve texto. Solo texto plano,
/// Markdown y PDF; nada se ejecuta ni se interpreta, y el archivo original no se toca.
nonisolated enum ContextImporter {
    enum Failure: Error, Equatable {
        case unsupported
        case tooLarge
        case unreadable
    }

    /// Lo que acepta el selector de archivos.
    static var allowedTypes: [UTType] {
        [.plainText, .pdf] + [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown")].compactMap { $0 }
    }

    /// Un archivo más grande que esto no es un resumen de proyecto.
    static let maxFileBytes = 5_000_000

    static func load(_ url: URL) throws -> ContextFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileBytes else { throw Failure.tooLarge }

        let title = url.lastPathComponent
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let text = PDFDocument(url: url)?.string, !text.isEmpty else { throw Failure.unreadable }
            return ContextFile(title: title, text: text)
        case "md", "markdown", "txt", "text":
            guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            else { throw Failure.unreadable }
            return ContextFile(title: title, text: text)
        default:
            throw Failure.unsupported
        }
    }
}
