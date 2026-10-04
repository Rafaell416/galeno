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
    @StateObject private var wizard = WizardState(draftStore: FileDraftStore())

    var body: some Scene {
        // `Window` y no `WindowGroup`: una sola ventana, nunca una segunda.
        Window("Galeno", id: "wizard") {
            WizardView()
                .environmentObject(wizard)
                .motionPreference()
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
            StepCommands(wizard: wizard)
        }

        Settings {
            SettingsView().environmentObject(wizard)
        }
        .windowResizability(.contentSize)
    }
}

/// El menú «Paso»: avanzar, volver y saltar a un paso ya visitado (⌘1…⌘0).
private struct StepCommands: Commands {
    @ObservedObject var wizard: WizardState

    var body: some Commands {
        CommandMenu("menu.step") {
            Button("menu.step.next") { wizard.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!wizard.canGoForward || wizard.hidesNavigation && wizard.step != .connect)
            Button("menu.step.back") { wizard.back() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!wizard.canGoBack)
            Divider()
            ForEach(WizardStep.allCases) { step in
                Button("menu.step.jump \(step.number)") { wizard.goTo(step) }
                    .keyboardShortcut(KeyEquivalent(Character(String(step.number % 10))), modifiers: .command)
                    .disabled(step.rawValue > wizard.furthestStep.rawValue || step == wizard.step)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// La ventana del wizard. Al cerrarla la app termina, aunque Ajustes siga abierto.
    weak static var wizardWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceChoice.stored.apply()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow, window === AppDelegate.wizardWindow else { return }
            NSApp.terminate(nil)
        }
    }

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
            AppDelegate.wizardWindow = window
            window.styleMask.remove(.resizable)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.center()
        }
    }
}
