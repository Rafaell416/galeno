import AppKit

/// Los cuatro sonidos de la app: una conexión lograda, algo que falló, el sello al llegar a «Listo» y, desde el
/// 6 oct 2026 (petición de Rafa), un toque suave al pulsar «Siguiente» en el asistente. Breves (≤ 450 ms), a volumen
/// bajo y generados por nosotros (`Sounds/*.wav`). **Encendidos de fábrica**; un solo interruptor en Ajustes los calla
/// todos. No hay ningún otro sonido (ni casillas, ni «Atrás», ni copiar).
@MainActor
enum Sounds {
    enum Cue: String, CaseIterable {
        /// Una herramienta quedó conectada.
        case connected = "conexion"
        /// Una conexión falló, o no se pudo escribir el agente.
        case failed = "fallo"
        /// El agente está listo.
        case seal = "sello"
        /// «Siguiente» desde el onboarding y en el asistente: una sola nota suave con un roce de papel. No suena al volver atrás.
        case step = "paso"
    }

    /// ≈ −12 dB sobre el volumen del sistema, que además manda (y su silencio también).
    static let volume: Float = 0.25

    private static var current: NSSound?

    /// Encendidos mientras nadie los apague en Ajustes.
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: Prefs.sounds) as? Bool ?? true }

    /// Las pruebas no suenan.
    private static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static func url(for cue: Cue) -> URL? { Bundle.main.url(forResource: cue.rawValue, withExtension: "wav") }

    static func play(_ cue: Cue) {
        guard isEnabled, !isTesting, let url = url(for: cue), let sound = NSSound(contentsOf: url, byReference: true)
        else { return }
        sound.volume = volume
        current?.stop()
        current = sound  // si no, se libera antes de sonar
        sound.play()
    }
}
