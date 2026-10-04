import GalenoCore
import SwiftUI

/// De dónde sale el logo de una herramienta.
enum ToolIconSource: Equatable {
    /// Un SVG del catálogo de assets (`Assets.xcassets/ToolIcons`).
    case asset(String)
    /// Un SF Symbol, para las herramientas que todavía no tienen logo.
    case symbol(String)
}

extension Tool {
    /// Los logos son monocromos y de Simple Icons (CC0); ver `THIRD_PARTY.md`.
    /// La excepción es Slack: su marca va en monocromo, de su identidad oficial (ver `THIRD_PARTY.md`).
    /// Fireflies y Granola no están en esa colección: llevan un símbolo del mismo color hasta que haya un SVG oficial.
    var iconSource: ToolIconSource {
        switch self {
        case .whatsapp: .asset("tool-whatsapp")
        case .notion: .asset("tool-notion")
        case .googleWorkspace: .asset("tool-googledrive")
        case .gmail: .asset("tool-gmail")
        case .jira: .asset("tool-jira")
        case .googleMeet: .asset("tool-googlemeet")
        case .fathom: .asset("tool-fathom")
        case .slack: .asset("tool-slack")
        case .fireflies: .symbol("waveform")
        case .granola: .symbol("note.text")
        // La marca de Claude Design es de Anthropic: hasta que haya un logo con licencia, un símbolo genérico.
        case .claudeDesign: .symbol("paintpalette")
        // Sin logo con licencia todavía: un símbolo genérico, como Fireflies y Granola.
        case .googleCalendar: .symbol("calendar")
        }
    }
}

/// El logo de una herramienta, en `ink-700` salvo que se pida otro tono de tinta (`docs/04` §7:
/// nada de color). La pantalla de conexión lo enciende en `ink-900` al conectar.
struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 28
    var color: Color = .ink700

    var body: some View {
        Group {
            switch tool.iconSource {
            case .asset(let name):
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            case .symbol(let name):
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.light)
            }
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
