import AppKit
import Foundation
import GalenoCore

/// Lo que el sub-wizard necesita del mundo: cómo hablar con `claude`, con el bridge de
/// WhatsApp y con el reloj. En producción es lo real; las pruebas y el modo de
/// depuración `-galeno-fake-connect` ponen conectores falsos.
@MainActor
struct ConnectServices {
    /// Recibe la ruta a `claude` que encontró el paso 2.
    var makeMCP: @MainActor (_ claudePath: String) -> any MCPConnecting
    var whatsapp: any WhatsAppLinking
    var slack: any SlackAppSetting = SlackAppSetupService()
    /// Muestra la autorización de Slack en una ventana de Galeno. `nil` (pruebas y conectores
    /// falsos) = se usa el navegador del sistema.
    var authorizer: (any SlackAuthorizationPresenting)?
    /// Muestra la autorización de las demás herramientas en la hoja de autenticación del sistema. `nil` (pruebas y
    /// conectores falsos) = se abre el navegador del sistema.
    var systemAuthorizer: (any SystemAuthorizationPresenting)?
    /// Lista lo que se puede elegir leer de cada herramienta (pantalla 6).
    var makeLister: @MainActor (_ claudePath: String) -> any SourceListing = { ClaudeSourceLister(claudePath: $0) }
    /// Escribe la carpeta del agente y lo registra en la instalación (pantalla 9).
    ///
    /// **Sin valor por defecto, a propósito:** escribe en `~/Galeno` y en `installation.json`. Quien
    /// construya esto elige: el real (`.live()`) o uno en una carpeta temporal.
    var installer: AgentInstaller
    /// Abre el agente (pantalla 10).
    var opener: any AgentOpening = SystemAgentOpener()
    /// De dónde se leen las skills (`catalog.json` y sus carpetas). En la app real, dentro del `.app`.
    var skillsDirectory: URL? = SkillsLocation.bundled()
    var fetchRealData: Bool = true
    var timing = ConnectFlow.Timing()
    var sleep: ConnectFlow.Sleeper = { _ = try? await Task.sleep(for: $0) }
    /// Trae Galeno al frente tras autorizar en el navegador. Las pruebas y los conectores falsos no lo hacen.
    var returnToApp: @MainActor () -> Void = {}
    /// Abre una dirección en el navegador del sistema. Las pruebas y los conectores falsos no abren nada.
    var openURL: @MainActor (URL) -> Void = { _ in }

    static func live() -> ConnectServices {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-galeno-fake-connect") {
            return .scripted()
        }
        #endif
        return ConnectServices(
            makeMCP: { ClaudeMCPClient(claudePath: $0) },
            whatsapp: WhatsAppBridge.live(),
            authorizer: SlackAuthorizeWindowPresenter(),
            systemAuthorizer: SystemAuthorizationSheet(),
            installer: .live(),
            returnToApp: { AppFocus.bringToFront() },
            openURL: { NSWorkspace.shared.open($0) })
    }
}

/// Dónde están las skills que se copian a la carpeta del agente.
nonisolated enum SkillsLocation {
    /// `Galeno.app/Contents/Resources/skills`, que una fase del proyecto copia desde `skills/`.
    /// En Debug, `-galeno-skills-path <ruta>` o `GALENO_SKILLS_PATH` la reemplazan.
    static func bundled(
        bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        #if DEBUG
        if let flag = arguments.firstIndex(of: "-galeno-skills-path"), arguments.indices.contains(flag + 1) {
            return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        }
        if let path = environment["GALENO_SKILLS_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return bundle.resourceURL?.appendingPathComponent("skills", isDirectory: true)
    }
}

extension AgentInstaller {
    /// El de verdad: `~/Galeno/<agente>/` y `~/Library/Application Support/Galeno/installation.json`.
    static func live(skillsDirectory: URL? = SkillsLocation.bundled()) -> AgentInstaller {
        AgentInstaller(
            options: ConfigGenerator.Options(
                // Si faltara, generar con skills marcadas dice cuál falta; sin skills, no hace falta.
                skillsDirectory: skillsDirectory ?? URL(fileURLWithPath: "/nonexistent/skills"),
                whatsAppBridgePath: BridgeLocation.installedBinary.path))
    }
}
