import AppKit
import GalenoCore
import SwiftUI

/// El personaje de un rol (decisión de Rafa, 6 oct 2026): cada oficio lo encarna una figura histórica, como quien
/// elige personaje. Galeno para producto, Josiah Wedgwood para marketing y Marco Polo para comercial. Es solo cómo
/// se ve: el rol sigue decidiendo las skills y el orden de las herramientas, y no cambia nada de la config.
struct Persona: Equatable {
    /// El nombre con el que se le llama en la app, igual en los dos idiomas (Marco Polo es «Marco», a secas).
    let name: String
    /// El retrato en `Assets.xcassets` (el del selector de rol). Puede faltar: se cae al dibujo del rol.
    let portrait: String
    /// La figura sentada de la mesa del home: una lámina del catálogo. Si falta, la mesa dibuja una de línea.
    let figure: String
    /// Cómo se sienta esa lámina a la mesa.
    let plate: FigurePlate

    var hasPortrait: Bool { NSImage(named: portrait) != nil }
    var hasFigure: Bool { NSImage(named: figure) != nil }
}

/// Las medidas de una lámina de figura (`THIRD_PARTY.md`): cada una viene de una imagen distinta, así que se ajusta
/// para que las cabezas midan lo mismo en la mesa.
struct FigurePlate: Equatable {
    /// Ancho entre alto de la imagen.
    let aspect: CGFloat
    /// Cuánto mide de alto en la mesa, en las unidades de la figura (a escala 1, puntos).
    let height: CGFloat
    /// Dónde está la mano que escribe, en fracciones de la imagen: es lo único que se mueve.
    let hand: CGRect
    /// La mesa sube hacia la derecha, así que el tablero deja ver más por la izquierda: la lámina que trae la mano a
    /// la derecha se sienta reflejada.
    var mirrored = false
}

extension AgentRole {
    var persona: Persona {
        switch self {
        case .productManager:
            Persona(
                name: "Galeno", portrait: "retrato-galeno", figure: "figura-galeno",
                plate: FigurePlate(aspect: 601.0 / 720, height: 110, hand: CGRect(x: 0.04, y: 0.77, width: 0.40, height: 0.18)))
        case .marketing:
            Persona(
                name: "Wedgwood", portrait: "retrato-wedgwood", figure: "figura-wedgwood",
                plate: FigurePlate(
                    aspect: 587.0 / 720, height: 118, hand: CGRect(x: 0.74, y: 0.77, width: 0.25, height: 0.21), mirrored: true))
        case .sales:
            Persona(
                name: "Marco", portrait: "retrato-polo", figure: "figura-polo",
                plate: FigurePlate(
                    aspect: 613.0 / 720, height: 108, hand: CGRect(x: 0.44, y: 0.80, width: 0.28, height: 0.16), mirrored: true))
        }
    }
}

/// Cómo se ve el home: la mesa con los personajes trabajando, o las tarjetas de siempre (que conservan todo:
/// estado, «Gestionar», regenerar una carpeta).
enum HomeLayout: String, CaseIterable, Identifiable {
    case table, cards
    var id: String { rawValue }
}
