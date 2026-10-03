// galeno-gen — herramienta de desarrollo.
//
// NO se distribuye y no es la interfaz del motor: GalenoApp (Fase 4) consume
// GalenoCore como librería directamente, nunca este binario. Esto existe
// solo para probar el generador a mano mientras se desarrolla, sin tener que
// escribir un AgentConfig en Swift cada vez. Ver docs/DEV.md.

import Foundation
import GalenoCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func printUsage() {
    print(
        """
        galeno-gen — genera la config de Claude Code a partir de un AgentConfig en JSON.
        Herramienta de desarrollo; no se distribuye. Ver docs/DEV.md.

        Si la carpeta ya tiene una config, la regenera: la deja exactamente como dice el
        JSON (quita las skills desmarcadas y el hook que ya no aplica) y no toca memoria/.
        Si algo falla, la carpeta queda como estaba.

        Uso:
          galeno-gen <config.json> <carpeta-destino> [opciones]

        Opciones:
          --skills-dir <ruta>            Carpeta con <galeno|curated>/<id>/SKILL.md.
                                          Por defecto, las skills de prueba del repo:
                                          \(defaultSkillsDirectory.path)
          --whatsapp-bridge-path <ruta>  Ruta del binario del bridge para .mcp.json.
                                          Por defecto, un valor de ejemplo:
                                          \(defaultWhatsAppBridgePath)
          -h, --help                     Muestra esto.
        """
    )
}

/// Las skills de prueba del repo: lo único que existe hoy (las reales son Fase 5).
/// Relativa al código fuente de este target, no al directorio de trabajo, para
/// que funcione sin importar desde dónde se invoque `swift run`.
let defaultSkillsDirectory = URL(filePath: #filePath)
    .deletingLastPathComponent()  // Sources/galeno-gen/
    .deletingLastPathComponent()  // Sources/
    .deletingLastPathComponent()  // GalenoCore/ (raíz del paquete)
    .appending(path: "Tests/Fixtures/skills", directoryHint: .isDirectory)

/// Un valor de ejemplo: en la app real, la ruta del binario empaquetado dentro
/// del .app (ver docs/03-especificacion-v0.0.1.md §4c).
let defaultWhatsAppBridgePath = "/Applications/Galeno.app/Contents/Resources/galeno-whatsapp"

// MARK: - Parseo de argumentos

var arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("-h") || arguments.contains("--help") || arguments.isEmpty {
    printUsage()
    exit(arguments.isEmpty ? 1 : 0)
}

var skillsDirectory = defaultSkillsDirectory
var whatsAppBridgePath = defaultWhatsAppBridgePath
var positional: [String] = []

var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--skills-dir":
        index += 1
        guard index < arguments.count else { fail("--skills-dir necesita una ruta.") }
        skillsDirectory = URL(filePath: arguments[index], directoryHint: .isDirectory)
    case "--whatsapp-bridge-path":
        index += 1
        guard index < arguments.count else { fail("--whatsapp-bridge-path necesita una ruta.") }
        whatsAppBridgePath = arguments[index]
    default:
        positional.append(argument)
    }
    index += 1
}

guard positional.count == 2 else {
    printUsage()
    fail("\nFaltan argumentos: se esperaban <config.json> y <carpeta-destino>.")
}

let configPath = positional[0]
let destinationPath = positional[1]

// MARK: - Generar

let configData: Data
do {
    configData = try Data(contentsOf: URL(filePath: configPath))
} catch {
    fail("No pude leer \"\(configPath)\": \(error.localizedDescription)")
}

let config: AgentConfig
do {
    config = try AgentConfig.jsonDecoder.decode(AgentConfig.self, from: configData)
} catch {
    fail("\"\(configPath)\" no es un AgentConfig válido: \(error)")
}

let destination = URL(filePath: destinationPath, directoryHint: .isDirectory)
let options = ConfigGenerator.Options(
    skillsDirectory: skillsDirectory,
    whatsAppBridgePath: whatsAppBridgePath
)

do {
    let result = try ConfigGenerator().generate(config, into: destination, options: options)

    print("Config de \"\(config.agentName)\" generada en \(destination.path):\n")
    for path in result.writtenFiles {
        print("  \(path)")
    }

    if !result.removedFiles.isEmpty {
        print("\nQuitado (ya no lo pide la config):")
        for path in result.removedFiles {
            print("  \(path)")
        }
    }

    if !result.warnings.isEmpty {
        print("\nAdvertencias:")
        for warning in result.warnings {
            print("  - \(warning)")
        }
    }
} catch let error as GenerationError {
    fail("No se pudo generar: \(error)")
} catch {
    fail("No se pudo generar: \(error.localizedDescription)")
}
