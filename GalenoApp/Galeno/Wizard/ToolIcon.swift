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
    /// Slack, Fireflies y Granola no están en esa colección: llevan un símbolo
    /// del mismo color hasta que haya un SVG oficial.
    var iconSource: ToolIconSource {
        switch self {
        case .whatsapp: .asset("tool-whatsapp")
        case .notion: .asset("tool-notion")
        case .googleWorkspace: .asset("tool-googledrive")
        case .gmail: .asset("tool-gmail")
        case .jira: .asset("tool-jira")
        case .googleMeet: .asset("tool-googlemeet")
        case .fathom: .asset("tool-fathom")
        case .slack: .symbol("number")
        case .fireflies: .symbol("waveform")
        case .granola: .symbol("note.text")
        }
    }
}

/// El logo de una herramienta, siempre en `ink-700` (`docs/04` §7: nada de color).
struct ToolIcon: View {
    let tool: Tool
    var size: CGFloat = 28

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
        .foregroundStyle(Color.ink700)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
