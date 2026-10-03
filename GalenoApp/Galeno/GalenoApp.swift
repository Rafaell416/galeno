import AppKit
import GalenoCore
import SwiftUI

/// La ventana del wizard: fija, 720×560.
enum WindowMetrics {
    static let width: CGFloat = 720
    static let height: CGFloat = 560
}

@main
struct GalenoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var wizard = WizardState()

    var body: some Scene {
        // `Window` y no `WindowGroup`: una sola ventana, nunca una segunda.
        Window("Galeno", id: "wizard") {
            WizardView()
                .environmentObject(wizard)
                // El idioma del paso 1 cambia toda la app en caliente. Por eso el código
                // no usa `String(localized:)`: no sigue `\.locale`.
                .environment(\.locale, Locale(identifier: wizard.language.rawValue))
                .frame(width: WindowMetrics.width, height: WindowMetrics.height)
                .background(WindowConfigurator())
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Un `pair` huérfano seguiría escuchando por su cuenta; un `claude mcp login`, esperando.
    func applicationWillTerminate(_ notification: Notification) {
        ProcessRegistry.shared.killAll()
    }
}

/// Deja la ventana fija: sin redimensionar, sin zoom, sin pantalla completa, y
/// centrada la primera vez.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguratorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguratorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask.remove(.resizable)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.center()
        }
    }
}
