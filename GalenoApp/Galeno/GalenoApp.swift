import AppKit
import GalenoCore
import SwiftUI

/// La ventana de Galeno: fija, 800×620 (decisión de Rafa, 5 oct 2026; antes 720×560, y así siguen
/// dibujados los archivos de Claude Design: mandan en disposición y proporciones, no en el tamaño exacto).
enum WindowMetrics {
    static let width: CGFloat = 800
    static let height: CGFloat = 620
}

@main
struct GalenoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppModel()
    @StateObject private var updates = UpdatesModel.live()

    var body: some Scene {
        // `Window` y no `WindowGroup`: una sola ventana, nunca una segunda.
        Window("Galeno", id: "wizard") {
            RootView(app: app)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) {}
            UpdateCommands(updates: updates)
            StepCommands(app: app)
        }

        Settings {
            SettingsView(app: app, updates: updates)
        }
        .windowResizability(.contentSize)
    }
}

/// La ventana: el home si ya hay agentes, el wizard si no (o con «Nuevo agente»).
private struct RootView: View {
    @ObservedObject var app: AppModel
    @Environment(\.galenoReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch app.screen {
            case .home:
                HomeView(
                    model: app.home, onNewAgent: app.startNewAgent, onManage: { app.openAgent($0) },
                    onAgentRemoved: app.agentRemoved, onHealth: app.openHealth)
                    .transition(reduceMotion ? .opacity : .pageTurn)
            case .agent:
                if let detail = app.agentDetail {
                    AgentDetailView(model: detail, onBack: app.closeAgent, onRemoved: app.agentRemovedFromDetail)
                        .id(detail.agentID)
                        .transition(reduceMotion ? .opacity : .pageTurn)
                }
            case .health:
                if let health = app.health {
                    HealthView(model: health, home: app.home, onBack: app.closeHealth)
                        .transition(reduceMotion ? .opacity : .pageTurn)
                }
            case .wizard:
                // Un wizard nuevo (otro objeto) empieza de cero también en lo local de cada vista.
                WizardView()
                    .id(ObjectIdentifier(app.wizard))
                    .environmentObject(app.wizard)
                    .environment(\.galenoFinishWizard, app.finishWizard)
                    .environment(\.galenoCancelWizard, app.cancelWizard)
                    .transition(reduceMotion ? .opacity : .pageTurn)
            }
        }
        .animation(reduceMotion ? nil : .pageTurn, value: app.screen)
        .motionPreference()
        // El idioma del paso 1 cambia toda la app en caliente. Por eso el código
        // no usa `String(localized:)`: no sigue `\.locale`.
        .environment(\.locale, Locale(identifier: app.language.rawValue))
        .frame(width: WindowMetrics.width, height: WindowMetrics.height)
        .background(WindowConfigurator())
    }
}

/// «Buscar actualizaciones…», en el menú de la app, bajo «Acerca de»: donde lo busca cualquiera en un Mac.
private struct UpdateCommands: Commands {
    @ObservedObject var updates: UpdatesModel

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("menu.updates.check") { updates.checkForUpdates() }
                .disabled(!updates.canCheck)
        }
    }
}

/// El menú «Paso»: avanzar, volver y saltar a un paso ya visitado (⌘1…⌘0).
private struct StepCommands: Commands {
    @ObservedObject var app: AppModel
    private var wizard: WizardState { app.wizard }
    /// El menú «Paso» solo vale con el wizard a la vista.
    private var inWizard: Bool { app.screen == .wizard }

    var body: some Commands {
        CommandMenu("menu.step") {
            Button("menu.step.next") { wizard.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!inWizard || !wizard.canGoForward || wizard.hidesNavigation && wizard.step != .connect)
            Button("menu.step.back") { wizard.back() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!inWizard || !wizard.canGoBack)
            Divider()
            ForEach(Array(wizard.stepOrder.enumerated()), id: \.element) { index, step in
                Button("menu.step.jump \(index + 1)") { wizard.goTo(step) }
                    .keyboardShortcut(KeyEquivalent(Character(String((index + 1) % 10))), modifiers: .command)
                    .disabled(!inWizard || step.rawValue > wizard.furthestStep.rawValue || step == wizard.step)
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
