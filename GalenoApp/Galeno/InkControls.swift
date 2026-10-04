import SwiftUI

// Los controles de formulario de B1: filete en vez de caja, tinta en vez de color.

// MARK: - Campo de texto

/// Un campo como una línea en el papel (`docs/04` §9): sin caja, solo un filete inferior de 1,5 pt
/// que se oscurece y engrosa al tener el foco. Lleva su propio estado de foco.
struct RuleTextField: View {
    private let title: LocalizedStringKey
    private let prompt: LocalizedStringKey
    @Binding private var text: String
    private let font: Font
    private let autofocus: Bool
    private let isError: Bool
    /// Cuántos renglones tiene el campo; con más de uno crece hacia abajo, como un área de texto.
    private let lines: Int
    @FocusState private var focused: Bool
    @Environment(\.galenoReduceMotion) private var reduceMotion

    init(
        _ title: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey,
        font: Font = Typo.text(17), autofocus: Bool = false, isError: Bool = false, lines: Int = 1
    ) {
        self.lines = lines
        self.title = title
        self.prompt = prompt
        self._text = text
        self.font = font
        self.autofocus = autofocus
        self.isError = isError
    }

    var body: some View {
        // El texto de ejemplo se dibuja aparte: el de `TextField` no respeta el color de tinta suave.
        ZStack(alignment: lines > 1 ? .topLeading : .leading) {
            if text.isEmpty {
                Text(prompt)
                    .font(font)
                    .foregroundStyle(Color.ink500)
                    .lineLimit(lines)
                    .padding(.top, lines > 1 ? 10 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // Sin título visible: en macOS un campo «plain» lo pinta como texto de ejemplo, encima
            // del nuestro. La etiqueta para VoiceOver va aparte.
            TextField("", text: $text, axis: lines > 1 ? .vertical : .horizontal)
                .lineLimit(lines > 1 ? 1...lines : 1...1)
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(font)
                .foregroundStyle(Color.ink900)
                .focused($focused)
                .padding(.top, lines > 1 ? 10 : 0)
                .padding(.bottom, lines > 1 ? 10 : 0)
        }
        .frame(minHeight: lines > 1 ? 44 + CGFloat(lines - 1) * 24 : 44, alignment: lines > 1 ? .top : .center)
        // La línea inferior: `ink-500`; al enfocar crece de izquierda a derecha hasta `ink-900` (200 ms);
        // con error pasa a lacre (150 ms).
        .overlay(alignment: .bottom) {
            ZStack(alignment: .leading) {
                Rectangle().fill(isError ? Color.seal700 : Color.ink500)
                Rectangle().fill(Color.ink900)
                    .scaleEffect(x: focused && !isError ? 1 : (reduceMotion ? 1 : 0), anchor: .leading)
                    .opacity(focused && !isError ? 1 : 0)
            }
            .frame(height: 1.5)
            .animation(.easeOut(duration: reduceMotion ? Motion.micro : 0.2), value: focused)
            .animation(.easeOut(duration: Motion.micro), value: isError)
        }
        .onAppear { if autofocus { focused = true } }
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Casilla

/// La casilla de B1: 16 pt, filete de 1,5 pt, marcada con relleno de tinta y una palomita.
/// El área que responde al clic es toda la fila.
struct InkCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        InkCheckboxBody(configuration: configuration)
    }
}

extension ToggleStyle where Self == InkCheckboxStyle {
    static var inkCheckbox: InkCheckboxStyle { InkCheckboxStyle() }
}

private struct InkCheckboxBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.galenoReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: Space.s8) {
                box.padding(.top, 2)
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
        .accessibilityValue(Text(configuration.isOn ? "✓" : ""))
    }

    /// Marcar: el fondo se rellena de tinta (150 ms) y la palomita se traza (180 ms). Desmarcar: todo se
    /// desvanece a la vez (120 ms).
    private var box: some View {
        let on = configuration.isOn
        return Rectangle()
            .strokeBorder(Color.ink700, lineWidth: 1.5)
            .background(Rectangle().fill(on ? Color.ink900 : Color.clear))
            .overlay {
                CheckMark()
                    .trim(from: 0, to: on ? 1 : 0)
                    .stroke(Color.onInk, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .padding(2)
                    .opacity(on ? 1 : 0)
                    .animation(
                        reduceMotion ? .easeOut(duration: Motion.micro)
                            : on ? .easeOut(duration: 0.18).delay(0.15) : .easeOut(duration: 0.12),
                        value: on)
            }
            .animation(.easeOut(duration: on ? Motion.micro : 0.12), value: on)
            .overlay {
                if isFocused {
                    Rectangle().strokeBorder(Color.seal700, lineWidth: 2).padding(-4)
                }
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }
}

// MARK: - Chip

/// Una opción que se enciende y se apaga (paso 6). 28 pt de alto; marcada = tinta rellena.
struct ChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration)
    }
}

extension ToggleStyle where Self == ChipToggleStyle {
    static var chip: ChipToggleStyle { ChipToggleStyle() }
}

private struct ChipBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isFocused) private var isFocused
    @State private var hovering = false

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(Typo.text(14))
                .lineLimit(1)
                .foregroundStyle(configuration.isOn ? Color.onInk : Color.ink900)
                .padding(.horizontal, 10)
                .frame(height: Control.chip)
                .background(
                    RoundedRectangle(cornerRadius: Radius.b1)
                        .fill(configuration.isOn ? Color.ink900 : hovering ? Color.parchment200 : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.b1)
                        .strokeBorder(configuration.isOn ? Color.ink900 : Color.ink300, lineWidth: 1.5)
                )
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: Radius.b1 + 2).strokeBorder(Color.seal700, lineWidth: 2).padding(-3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

// MARK: - Selector segmentado

/// Dos o tres opciones en una sola caja con filete de 1,5 pt (idioma, «Preguntarme / Sin preguntar»).
/// La elegida va en tinta rellena.
struct InkSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    var padding: CGFloat = 14
    var fontSize: CGFloat = 14
    /// Las opciones que, elegidas, se rellenan en lacre con texto blanco en vez de en tinta: las
    /// que conviene que se noten («Sin preguntar»).
    var accented: Set<Value> = []
    let label: (Value) -> Text

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @Namespace private var slide

    init(
        selection: Binding<Value>, options: [Value], padding: CGFloat = 14, fontSize: CGFloat = 14,
        accented: Set<Value> = [], label: @escaping (Value) -> Text
    ) {
        self._selection = selection
        self.options = options
        self.padding = padding
        self.fontSize = fontSize
        self.accented = accented
        self.label = label
    }

    private var fill: Color { accented.contains(selection) ? .seal700 : .ink900 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let on = option == selection
                Button {
                    selection = option
                } label: {
                    label(option)
                        .font(Typo.text(fontSize, .medium))
                        .lineLimit(1)
                        .foregroundStyle(on ? (accented.contains(option) ? Color.white : Color.onInk) : Color.ink900)
                        .padding(.horizontal, padding)
                        .frame(height: 34)
                        // El relleno no salta: se desliza de una opción a la otra (180 ms).
                        .background {
                            if on {
                                Rectangle().fill(fill)
                                    .matchedGeometryEffect(id: "fill", in: slide)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
                if index < options.count - 1 {
                    Rectangle().fill(Color.ink900).frame(width: 1.5)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selection)
        .clipShape(RoundedRectangle(cornerRadius: Radius.b1))
        .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
        .fixedSize()
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .contain)
    }
}

/// «Copiar» → «Copiado» sin que el botón cambie de ancho: ambas cadenas reservan el sitio y el texto
/// visible cambia con un fundido de 150 ms.
struct CopyLabel: View {
    let copied: Bool
    var idle: LocalizedStringKey
    var done: LocalizedStringKey = "done.copied"

    var body: some View {
        ZStack {
            Text(idle).hidden()
            Text(done).hidden()
            Text(copied ? done : idle)
                .id(copied)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: Motion.micro), value: copied)
    }
}

// MARK: - Fila que se acomoda

/// Reparte sus hijos en renglones, como las palabras de un párrafo (los chips del paso 6).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    /// Si se dan, separación vertical y horizontal distintas de `spacing`.
    var lineSpacing: CGFloat?
    var itemSpacing: CGFloat?

    private var gapX: CGFloat { itemSpacing ?? spacing }
    private var gapY: CGFloat { lineSpacing ?? spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + gapY; rowHeight = 0
            }
            x += size.width + gapX
            maxX = max(maxX, x - gapX)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + gapY; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + gapX
            rowHeight = max(rowHeight, size.height)
        }
    }
}
