import XCTest

@testable import Galeno

/// Las actualizaciones con Sparkle (`docs/03` §4f): lo que el `Info.plist` promete —nada de perfil del sistema, una
/// clave pública de verdad— y cuándo la app busca y cuándo no. Ninguna prueba hace una petición.
@MainActor
final class UpdatesTests: XCTestCase {
    private func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }

    /// La petición al appcast no lleva perfil del sistema: está apagado en el `Info.plist`, que es de donde lo lee Sparkle.
    func testTheAppNeverSendsASystemProfile() {
        XCTAssertEqual(info("SUEnableSystemProfiling") as? Bool, false)
    }

    /// Mira sola, sin preguntarle antes al usuario si quiere que mire.
    func testTheAppChecksOnItsOwn() {
        XCTAssertEqual(info("SUEnableAutomaticChecks") as? Bool, true)
        XCTAssertEqual(info("SUScheduledCheckInterval") as? Int, 86_400)
    }

    /// La clave con que se comprueba cada actualización es una clave Ed25519 de verdad (32 bytes), no un relleno.
    func testThePublicKeyIsARealOne() throws {
        let text = try XCTUnwrap(info("SUPublicEDKey") as? String)
        XCTAssertEqual(Data(base64Encoded: text)?.count, 32)
    }

    /// La dirección del appcast va por `https` y sin parámetros: nada que identifique a nadie.
    func testTheFeedIsHTTPSAndCarriesNoParameters() throws {
        let feed = try XCTUnwrap(UpdatesModel.feedURL)
        XCTAssertEqual(feed.scheme, "https")
        XCTAssertNil(feed.query)
        XCTAssertNil(feed.fragment)
        XCTAssertNil(feed.user)
    }

    /// Con la dirección de relleno (el sitio no existe todavía) no se busca nada; con una de verdad, sí.
    func testOnlyARealFeedCounts() {
        XCTAssertFalse(UpdatesModel.isConfigured(feed: URL(string: "https://galeno.invalid/appcast.xml")))
        XCTAssertFalse(UpdatesModel.isConfigured(feed: URL(string: "http://ejemplo.com/appcast.xml")), "sin https, no")
        XCTAssertFalse(UpdatesModel.isConfigured(feed: nil))
        XCTAssertTrue(UpdatesModel.isConfigured(feed: URL(string: "https://ejemplo.com/appcast.xml")))
    }

    /// Bajo las pruebas la app no arranca Sparkle: ni peticiones ni ventanas. Y apagada, «Buscar» no hace nada.
    func testUnderTestsNothingIsStarted() {
        let live = UpdatesModel.live()
        XCTAssertFalse(live.isEnabled)
        XCTAssertFalse(live.canCheck)
        live.checkForUpdates()

        let off = UpdatesModel(enabled: false)
        XCTAssertFalse(off.isEnabled)
        XCTAssertFalse(off.canCheck)
    }

    func testTheVersionIsReadFromTheApp() {
        XCTAssertTrue(UpdatesModel.version.contains("("), UpdatesModel.version)
        XCTAssertFalse(UpdatesModel.version.contains("—"), "la app sabe su versión")
    }
}
