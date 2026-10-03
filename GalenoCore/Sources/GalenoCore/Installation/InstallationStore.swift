import Foundation

/// Lee y escribe la instalación en `~/Library/Application Support/Galeno/installation.json`.
public struct InstallationStore: Sendable {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Galeno", directoryHint: .isDirectory)
    }

    public static let fileName = "installation.json"

    public let directory: URL

    public init(directory: URL = InstallationStore.defaultDirectory) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appending(path: Self.fileName) }

    /// La instalación guardada, o `nil` si no hay ninguna: es la primera vez y
    /// la app abre el wizard.
    ///
    /// Un archivo que existe pero no se puede leer **lanza un error y no se
    /// toca**: puede ser lo único que recuerda los agentes, y pisarlo con una
    /// instalación vacía los perdería. Igual uno guardado por una versión más
    /// nueva de la app.
    public func load() throws -> GalenoInstallation? {
        let path = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw InstallationError.unreadable(path: path, reason: error.localizedDescription)
        }

        struct VersionOnly: Decodable { var schemaVersion: Int }
        do {
            let found = try JSONDecoder().decode(VersionOnly.self, from: data).schemaVersion
            if found > GalenoInstallation.currentSchemaVersion {
                throw InstallationError.newerThanThisApp(
                    found: found, supported: GalenoInstallation.currentSchemaVersion)
            }
            return try JSONDecoder().decode(GalenoInstallation.self, from: data)
        } catch let error as InstallationError {
            throw error
        } catch {
            throw InstallationError.unreadable(path: path, reason: "\(error)")
        }
    }

    /// Escribe la instalación de forma atómica: o queda el archivo nuevo
    /// completo o el anterior, nunca a medias.
    public func save(_ installation: GalenoInstallation) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(installation).write(to: fileURL, options: .atomic)
    }
}
