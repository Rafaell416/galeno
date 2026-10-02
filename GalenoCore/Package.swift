// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GalenoCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GalenoCore", targets: ["GalenoCore"])
    ],
    targets: [
        .target(name: "GalenoCore"),
        // Herramienta de desarrollo. No se distribuye: GalenoApp (Fase 4)
        // consume GalenoCore como librería, nunca este binario. Ver
        // docs/DEV.md. No rompe la regla "el motor es interno, sin CLI de
        // cara al usuario": esto es para quien trabaja en el repo, no para
        // un cliente de Galeno.
        .executableTarget(name: "galeno-gen", dependencies: ["GalenoCore"]),
        .testTarget(name: "GalenoCoreTests", dependencies: ["GalenoCore"])
    ]
)
