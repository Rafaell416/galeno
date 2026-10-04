import AppKit

/// Trae Galeno al frente. Se usa cuando el usuario termina de autorizar una herramienta en su navegador:
/// la pestaña se queda abierta allá (Galeno no puede cerrarla), pero él vuelve solo al asistente.
@MainActor
enum AppFocus {
    static func bringToFront() {
        // Desde macOS 14 la activación es cooperativa: una app en segundo plano no siempre puede ponerse
        // delante por su cuenta. Abrirse a sí misma por LaunchServices sí la trae al frente, igual que si
        // el usuario pulsara su icono en el Dock; no crea otra instancia.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        NSApp.activate()
        NSApp.windows.first { $0.isVisible && $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
    }
}
