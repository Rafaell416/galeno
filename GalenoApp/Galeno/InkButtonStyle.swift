import SwiftUI

/// Los botones de B1 («El impresor»): tinta sobre papel, sin sombra, esquinas de 4 pt.
///
/// - `primary`: relleno `ink-900`, texto `onInk`. Solo uno por pantalla; es la acción siguiente.
/// - `secondary`: filete de 1,5 pt en `ink-900`, fondo transparente.
/// - `tertiary`: solo texto subrayado, para lo discreto ("Más tarde", "Volver a las herramientas").
///
/// Dos alturas: `regular` (44 pt, la barra de navegación y las acciones que cierran un paso) y
/// `bar` (36 pt, acciones dentro del contenido: copiar, reintentar, abrir una página).
/// El acento (`seal-700`) solo aparece en el botón destructivo y en el anillo de foco.
struct InkButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, tertiary }
    enum Size {
        case regular, bar

        var height: CGFloat { self == .regular ? Control.primary : Control.bar }
        var padding: CGFloat { self == .regular ? 22 : 14 }
        var fontSize: CGFloat { self == .regular ? 16 : 14 }
    }

    var kind: Kind = .primary
    var size: Size = .regular
    /// El margen horizontal, cuando el diseño pide uno distinto del de su tamaño.
    var padding: CGFloat?
    /// Secundario discreto: filete y texto en gris (`parchment-400` / `ink-700`).
    var quiet = false
    /// Una altura distinta de la de su tamaño (el botón de 48 pt del conflicto de nombre).
    var height: CGFloat?
    /// Mientras algo se hace: conserva el ancho, esconde la etiqueta y muestra una rueda.
    var isLoading = false

    init(
        _ kind: Kind = .primary, size: Size = .regular, padding: CGFloat? = nil, quiet: Bool = false,
        height: CGFloat? = nil, isLoading: Bool = false
    ) {
        self.height = height
        self.kind = kind
        self.size = size
        self.padding = padding
        self.quiet = quiet
        self.isLoading = isLoading
    }

    func makeBody(configuration: Configuration) -> some View {
        InkButtonBody(
            configuration: configuration, kind: kind, size: size, padding: padding ?? size.padding,
            quiet: quiet, height: height ?? size.height, isLoading: isLoading)
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var inkPrimary: InkButtonStyle { InkButtonStyle(.primary) }
    static var inkSecondary: InkButtonStyle { InkButtonStyle(.secondary) }
    static var inkTertiary: InkButtonStyle { InkButtonStyle(.tertiary) }
    /// Secundario de 36 pt, para acciones dentro del contenido.
    static var inkInline: InkButtonStyle { InkButtonStyle(.secondary, size: .bar) }
}

private struct InkButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: InkButtonStyle.Kind
    let size: InkButtonStyle.Size
    let padding: CGFloat
    let quiet: Bool
    let height: CGFloat
    let isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var hovering = false
    /// Cuánto del anillo de foco está trazado (0…1).
    @State private var ring: CGFloat = 0

    private var destructive: Bool { configuration.role == .destructive }
    private var stroke: Color { destructive ? .seal700 : quiet ? .parchment400 : .ink900 }
    private var ink: Color { destructive ? .seal700 : quiet ? .ink700 : .ink900 }

    var body: some View {
        label
            .opacity(isEnabled ? (configuration.isPressed && kind != .primary ? 0.7 : 1) : 0.4)
            // Pulsado: baja 1 pt (80 ms). Hover: 150 ms.
            .offset(y: configuration.isPressed ? 1 : 0)
            .onHover { hovering = $0 }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: Motion.micro), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .animation(.easeOut(duration: Motion.micro), value: isLoading)
            .onChange(of: isFocused) { _, focused in
                withAnimation(.easeOut(duration: reduceMotion ? 0 : Motion.micro)) { ring = focused ? 1 : 0 }
            }
    }

    @ViewBuilder
    private var label: some View {
        switch kind {
        case .tertiary:
            text
                .foregroundStyle(hovering ? Color.ink900 : Color.ink700)
                // El subrayado pasa de `ink-300` a `ink-900` con el puntero.
                .underline(!quiet, color: hovering ? Color.ink900 : Color.ink300)
                .frame(minHeight: height)
                .overlay(focusRing)
        case .primary, .secondary:
            ZStack {
                text.opacity(isLoading ? 0 : 1)
                // Cargando: el texto baja a opacidad 0 (el ancho no cambia) y un anillo de 12 pt se traza y gira.
                if isLoading { LoadingRing(color: kind == .primary ? Color.onInk : Color.ink900) }
            }
            .foregroundStyle(kind == .primary ? Color.onInk : ink)
            .padding(.horizontal, padding)
            .frame(minHeight: height)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.b1)
                    .strokeBorder(stroke, lineWidth: kind == .secondary ? 1.5 : 0)
            )
            .overlay(focusRing)
        }
    }

    private var text: some View {
        configuration.label
            .font(Typo.text(kind == .tertiary ? 15 : size.fontSize, .medium))
            .lineLimit(1)
    }

    /// Primario: de `ink-900` a `ink-700` al pasar el puntero. Secundario: un velo de pergamino.
    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.b1)
        if kind == .primary {
            shape.fill(configuration.isPressed ? Color.inkPressed : hovering ? Color.ink700 : Color.ink900)
        } else {
            shape.fill(configuration.isPressed || hovering ? Color.parchment100 : Color.clear)
        }
    }

    /// El anillo de foco por teclado: 2 pt en `seal-700`, a 2 pt del borde, que se dibuja al enfocar.
    private var focusRing: some View {
        Rectangle()
            .trim(from: 0, to: reduceMotion ? (isFocused ? 1 : 0) : ring)
            .stroke(Color.seal700, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
            .padding(-4)
            .allowsHitTesting(false)
    }
}
