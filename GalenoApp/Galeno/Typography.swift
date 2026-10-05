import AppKit
import CoreText
import SwiftUI

private final class BundleToken {}

/// Las fuentes del rediseño B1 («El impresor»): Cormorant Garamond para los títulos y EB Garamond
/// para el texto. Son las TTF variables de Google Fonts (OFL), subconjuntadas a latino
/// (`docs/05b-spike-fuentes.md`) y registradas en tiempo de ejecución, sin `Info.plist`.
/// Si algo falla, cada fuente cae a New York y la app sigue siendo legible.
enum GalenoFonts {
    /// Los nombres PostScript que usa la escala. Un test comprueba que cargan.
    static let postScriptNames = [
        "CormorantGaramond-SemiBold",
        "CormorantGaramond-MediumItalic",
        "EBGaramond-Regular",
        "EBGaramond-Medium",
        "EBGaramond-SemiBold",
        "EBGaramond-Italic",
    ]

    /// Se evalúa una sola vez, la primera vez que se pide una fuente.
    private static let registered: Bool = registerBundledFonts()

    /// Registra las fuentes del paquete. Devuelve `true` si había alguna.
    @discardableResult
    static func registerBundledFonts(in bundle: Bundle = Bundle(for: BundleToken.self)) -> Bool {
        let urls =
            (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
            + (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
        for url in urls {
            // Si ya estaba registrada devuelve `false`; no es un error.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return !urls.isEmpty
    }

    /// `true` si el nombre PostScript se resuelve a una fuente real (no a la de respaldo).
    static func isAvailable(_ postScriptName: String) -> Bool {
        _ = registered
        return NSFont(name: postScriptName, size: 12) != nil
    }

    fileprivate static func face(
        _ postScriptName: String, size: CGFloat, fallbackWeight: Font.Weight, italic: Bool = false
    ) -> Font {
        if isAvailable(postScriptName) { return .custom(postScriptName, fixedSize: size) }
        let fallback = Font.system(size: size, weight: fallbackWeight, design: .serif)
        return italic ? fallback.italic() : fallback
    }
}

/// La escala tipográfica de B1 (`docs/05` §A). El texto del cuerpo nunca baja de 14.
/// Los tamaños son fijos: la ventana es de 800×620 y no escala con Dynamic Type.
enum Typo {
    /// Cormorant Garamond: portada y títulos. `italic` usa Medium Italic.
    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        GalenoFonts.face(
            italic ? "CormorantGaramond-MediumItalic" : "CormorantGaramond-SemiBold",
            size: size, fallbackWeight: italic ? .medium : .semibold, italic: italic)
    }

    /// EB Garamond: todo el texto.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let name =
            italic
            ? "EBGaramond-Italic"
            : weight == .regular
                ? "EBGaramond-Regular" : weight == .medium ? "EBGaramond-Medium" : "EBGaramond-SemiBold"
        return GalenoFonts.face(name, size: size, fallbackWeight: weight, italic: italic)
    }

    static var pageTitle: Font { display(36) }
    static var stepTitle: Font { display(32) }
    static var quote: Font { display(26, italic: true) }
    static var body: Font { text(16) }
    static var list: Font { text(15) }
    static var note: Font { text(13.5) }
    /// Etiqueta en versalitas. Va con `.galenoLabel()` para el espaciado. Solo para palabras: en
    /// EB Garamond las cifras en versalitas son de estilo antiguo y «10» se lee «Io».
    static var label: Font { text(13, .medium).smallCaps() }
    /// Rótulo con cifras («PASO 3 DE 10»): mayúsculas pequeñas en vez de versalitas. Va con `.galenoKicker()`.
    static var kicker: Font { text(12, .medium) }
    static var mono: Font { .system(size: 13, design: .monospaced) }
}

/// Una cadena ya resuelta en el idioma que eligió el usuario. Se usa solo donde hace falta el texto
/// como `String` (para partirlo en tramos); lo demás va con claves en `Text`, que siguen `\.locale`.
/// No es `String(localized:)`: lee el `.lproj` del idioma del wizard, así que cambia en caliente.
enum Localized {
    static func string(_ key: String, _ arguments: CVarArg..., locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "es"
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }
}

/// Versalitas como las pinta el diseño: las minúsculas pasan a mayúsculas al 70 % del tamaño y lo
/// demás (mayúsculas, cifras, signos) queda al tamaño completo. No se usa la característica `smcp`
/// de la fuente: sus versalitas son más anchas que las del diseño y convierten las cifras a estilo
/// antiguo («10» se leería «Io»).
struct SmallCapsText: View {
    let string: String
    var size: CGFloat = 13
    var weight: Font.Weight = .regular
    /// En `em`, como en el diseño (0,14 em = 1,8 pt a 13 pt).
    var tracking: CGFloat = 0.14

    var body: some View {
        runs.kerning(size * tracking)
    }

    private var runs: Text {
        var result = Text(verbatim: "")
        var buffer = ""
        var bufferIsSmall = false
        func flush() {
            guard !buffer.isEmpty else { return }
            result = result
                + Text(verbatim: bufferIsSmall ? buffer.uppercased() : buffer)
                .font(Typo.text(bufferIsSmall ? size * 0.7 : size, weight))
            buffer = ""
        }
        for character in string {
            let isSmall = character.isLowercase
            if isSmall != bufferIsSmall { flush(); bufferIsSmall = isSmall }
            buffer.append(character)
        }
        flush()
        return result
    }
}

/// Lo mismo, a partir de una clave del catálogo: se resuelve en el idioma del wizard.
struct SmallCapsLabel: View {
    let key: String
    var size: CGFloat = 13
    var tracking: CGFloat = 0.12
    @Environment(\.locale) private var locale

    init(_ key: String, size: CGFloat = 13, tracking: CGFloat = 0.12) {
        self.key = key
        self.size = size
        self.tracking = tracking
    }

    var body: some View {
        SmallCapsText(string: Localized.string(key, locale: locale), size: size, tracking: tracking)
    }
}

extension View {
    /// Mayúsculas pequeñas con espaciado, para los rótulos que llevan números.
    func galenoKicker() -> some View {
        font(Typo.kicker).textCase(.uppercase).kerning(1.8)
    }

    /// Versalitas de EB Garamond con el espaciado de B1 (≈ 0,14 em a 13 pt).
    func galenoLabel() -> some View {
        font(Typo.label).kerning(1.8)
    }
}

/// Las esquinas de B1 son rectas, como las del prototipo. Solo las tarjetas de «Revisión» redondean.
enum Radius {
    static let b1: CGFloat = 0
    static let card: CGFloat = 4
}

/// Alturas de los controles de B1.
enum Control {
    static let primary: CGFloat = 44
    static let bar: CGFloat = 36
    static let chip: CGFloat = 28
}
