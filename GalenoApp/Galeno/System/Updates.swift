import Combine
import Foundation
import Sparkle

/// Las actualizaciones de la app (capa 1 de `docs/03` §4f), con Sparkle: la app mira el appcast al abrir y desde
/// «Buscar actualizaciones», y si hay una versión nueva la descarga, comprueba su firma y se reemplaza.
///
/// **Es solo una descarga.** La petición al appcast no lleva perfil del sistema ni ningún dato del usuario
/// (`SUEnableSystemProfiling` en falso, y aquí otra vez por si alguien lo cambia en el plist): lo único que viaja es
/// lo que lleva cualquier petición web y el nombre y la versión de la app en la cabecera. No añadir identificadores,
/// conteos de uso ni parámetros a la dirección del appcast (`AGENTS.md`, «Actualizaciones»).
///
/// **Una actualización solo se instala si la firmó Galeno**: Sparkle comprueba la firma EdDSA con la clave pública
/// del `Info.plist` (`SUPublicEDKey`); la privada vive en el llavero de quien publica, fuera del repo.
///
/// La ventana de «hay una versión nueva» es la de Sparkle, la estándar de macOS, y sale en el idioma del sistema.
@MainActor
final class UpdatesModel: ObservableObject {
    /// ¿Se puede buscar ahora? Falso mientras ya hay una búsqueda en curso, o si esta compilación no busca.
    @Published private(set) var canCheck = false

    private let controller: SPUStandardUpdaterController?
    private var observer: AnyCancellable?

    /// Con `enabled` en falso no se crea nada de Sparkle: ni peticiones, ni temporizadores, ni ventanas.
    init(enabled: Bool) {
        guard enabled else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.sendsSystemProfile = false
        self.controller = controller
        observer = controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] value in
            self?.canCheck = value
        }
        // Al abrir, sin esperar al calendario de Sparkle (una vez al día). En silencio: solo avisa si hay algo nuevo.
        if !controller.updater.sessionInProgress { controller.updater.checkForUpdatesInBackground() }
    }

    /// La de la app que se usa. No busca cuando la app corre como anfitriona de las pruebas, ni mientras la dirección
    /// del appcast sea la de relleno (el sitio todavía no existe).
    static func live() -> UpdatesModel {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        return UpdatesModel(enabled: !testing && isConfigured(feed: feedURL))
    }

    /// La dirección del appcast, del `Info.plist`.
    static var feedURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))
    }

    /// ¿Apunta a un appcast de verdad? Tiene que ser `https` y no la de relleno: `.invalid` es un dominio reservado
    /// que no existe nunca, y es lo que lleva el `Info.plist` hasta que el sitio tenga el suyo.
    static func isConfigured(feed: URL?) -> Bool {
        guard let feed, feed.scheme == "https", let host = feed.host, !host.isEmpty else { return false }
        return !host.hasSuffix(".invalid")
    }

    /// ¿Esta compilación sabe actualizarse sola?
    var isEnabled: Bool { controller != nil }

    /// «Buscar actualizaciones»: lo pidió el usuario, así que Sparkle responde siempre, haya o no versión nueva.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// «0.0.1 (2)»: la versión y el número de compilación de esta app.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
