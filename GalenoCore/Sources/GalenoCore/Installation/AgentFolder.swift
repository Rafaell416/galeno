import Foundation

/// Dónde vive la carpeta de cada agente: `~/Galeno/<agente>/`.
///
/// Es una carpeta visible, a propósito: el usuario puede abrirla en Terminal o
/// en la app de Claude sin buscarla. La ruta se elige una vez, al crear el
/// agente, y se guarda; renombrar el agente después no la mueve sola.
public enum AgentFolder {
    /// `~/Galeno`.
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Galeno", directoryHint: .isDirectory)
    }

    /// Tope del nombre de la carpeta, en caracteres.
    public static let maximumNameLength = 60

    /// El nombre cuando el del agente no deja nada utilizable.
    public static let fallbackName = "Agente"

    /// Convierte el nombre del agente en un nombre de carpeta seguro.
    ///
    /// Quita lo que rompe una ruta (`/`, `:`, `\`, caracteres de control),
    /// colapsa los espacios, quita los puntos del inicio (nada de `..` ni
    /// carpetas ocultas) y recorta. Los acentos y las eñes se conservan.
    public static func sanitized(_ name: String) -> String {
        var cleaned = ""
        for scalar in name.precomposedStringWithCanonicalMapping.unicodeScalars {
            if "/:\\".unicodeScalars.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.newlines.contains(scalar)
            {
                cleaned.unicodeScalars.append(" ")
            } else {
                cleaned.unicodeScalars.append(scalar)
            }
        }

        let words = cleaned.split(whereSeparator: \.isWhitespace)
        var result = words.joined(separator: " ")
        result = String(result.drop(while: { $0 == "." || $0 == " " }))
        result = String(result.prefix(maximumNameLength))
        while result.last == " " { result.removeLast() }

        return result.isEmpty ? fallbackName : result
    }

    /// La carpeta para un agente nuevo: `<root>/<nombre saneado>`, o con un
    /// número (`Aurora 2`, `Aurora 3`…) si ya hay una igual.
    ///
    /// Choca con las carpetas de los otros agentes (`taken`), aunque ya no
    /// existan en disco, y con lo que ya exista en disco, que puede no ser de
    /// Galeno: una carpeta `Aurora` del usuario no se pisa. La comparación no
    /// distingue mayúsculas ni la forma Unicode de los acentos, porque el
    /// sistema de archivos de macOS tampoco.
    public static func uniqueFolder(
        for name: String,
        in root: URL,
        avoiding taken: [URL] = [],
        fileManager: FileManager = .default
    ) -> URL {
        func key(_ url: URL) -> String {
            url.standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
        }

        let takenKeys = Set(taken.map(key))
        let base = sanitized(name)

        var candidate = root.appending(path: base, directoryHint: .isDirectory)
        var number = 2
        while takenKeys.contains(key(candidate)) || fileManager.fileExists(atPath: candidate.path) {
            candidate = root.appending(path: "\(base) \(number)", directoryHint: .isDirectory)
            number += 1
        }
        return candidate
    }
}
