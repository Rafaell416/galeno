import AppKit
import GalenoCore
import SwiftUI

/// La mesa del home: cada agente es su personaje, sentado a una mesa larga vista en diagonal, con su nombre encima.
/// Un clic lo abre en Claude, igual que «Abrir» en su tarjeta (el mismo `HomeModel.open`).
///
/// **El personaje solo escribe si su agente trabajó hace poco** (`HomeModel.isWorking`, que sale de la última
/// actividad de su sesión): un movimiento de ambiente fingiría un trabajo que Galeno no conoce. Con «Reducir
/// movimiento», nadie se mueve. Lo que la mesa no enseña —el estado, «Gestionar», regenerar una carpeta— sigue en
/// las tarjetas, a un interruptor de distancia.
struct HomeTableView: View {
    @ObservedObject var model: HomeModel
    let onManage: (UUID) -> Void
    /// Pasar a las tarjetas: donde se arregla un agente sin carpeta.
    let onShowCards: () -> Void

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @State private var table = 0
    @State private var hovered: UUID?
    /// Dónde se desplegó el menú del clic derecho, en el lienzo de la mesa.
    @State private var menuAt: CGPoint?
    /// Los agentes con actividad reciente, mirados cada pocos segundos mientras la mesa está a la vista.
    @State private var working: Set<UUID> = []

    private var tables: [[MesaSeat]] { Mesa.tables(for: model.agents) }
    private var current: Int { min(table, max(tables.count - 1, 0)) }
    private var seats: [MesaSeat] { tables.isEmpty ? [] : tables[current] }
    /// De lo lejano a lo cercano: el de delante se dibuja encima.
    private var drawOrder: [MesaSeat] { seats.sorted { $0.position > $1.position } }

    var body: some View {
        VStack(spacing: 0) {
            scene
            caption
                .frame(height: 44, alignment: .center)
                .padding(.horizontal, Space.s48)
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .task(id: model.agents.map(\.id)) {
            // Solo mientras la mesa está en pantalla: al salir, la tarea se cancela.
            while !Task.isCancelled {
                await model.refreshActivity()
                working = Set(model.agents.filter { model.isWorking($0) }.map(\.id))
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    // MARK: La escena

    private var scene: some View {
        ZStack {
            // Detrás del tablero, que les tapa la cintura: las figuras de línea (quien no tiene lámina o carpeta).
            ForEach(drawOrder.filter { !usesPlate($0) }) { seat in
                FigureLayer(seat: seat, plate: false, highlighted: hovered == seat.id, writes: false, dimmed: false)
                    .staggered(order(of: seat))
                    .transition(.opacity)
            }
            Canvas { context, _ in MesaDrawing.table(&context, dimmed: colorScheme == .dark) }
                .allowsHitTesting(false)
            // Encima del tablero: las láminas, apoyadas en él con las manos y el papel sobre la madera; y, para una
            // figura de línea, su papel y el brazo que escribe.
            ForEach(drawOrder) { seat in
                if usesPlate(seat) {
                    FigureLayer(
                        seat: seat, plate: true, highlighted: hovered == seat.id,
                        writes: working.contains(seat.id) && !reduceMotion, dimmed: colorScheme == .dark
                    )
                    .staggered(order(of: seat))
                    .transition(.opacity)
                } else if seat.agent.folderExists {
                    DeskLayer(
                        seat: seat, plate: false, highlighted: hovered == seat.id,
                        writes: working.contains(seat.id) && !reduceMotion
                    )
                    .staggered(order(of: seat))
                    .transition(.opacity)
                }
            }
            // El nombre va encima de lo que responde al clic: su engranaje tiene que recibir el suyo.
            ForEach(seats) { seat in
                hitArea(seat)
                nameTag(seat)
            }
            if tables.count > 1 { pager }
            if let seat = seats.first(where: { $0.id == model.menuOpen }) {
                seatMenu(seat)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .frame(width: Mesa.size.width, height: Mesa.size.height)
        // El clic derecho (o con Control) sobre un personaje abre su menú; en cualquier otro sitio, lo cierra.
        .background { SecondaryClickMonitor { point in secondaryClick(at: point) } }
        .animation(.easeOut(duration: Motion.micro), value: model.menuOpen)
        .animation(.easeOut(duration: Motion.enter), value: seats.map(\.id))
        .accessibilityElement(children: .contain)
    }

    /// ¿Se sienta este agente como lámina? Sin carpeta va siempre la silueta de línea.
    private func usesPlate(_ seat: MesaSeat) -> Bool { seat.agent.folderExists && seat.agent.role.persona.hasFigure }

    /// Cuánto sobresale la figura de este sitio: de ahí cuelga su nombre.
    private func rise(_ seat: MesaSeat) -> CGFloat {
        usesPlate(seat) ? seat.agent.role.persona.plate.height - Mesa.plateSink : Mesa.drawnRise
    }

    /// El orden en que aparecen: como se sentaron.
    private func order(of seat: MesaSeat) -> Int { Mesa.fillOrder.firstIndex(of: seat.position) ?? 0 }

    /// El nombre sobre la cabeza. Al pasar el cursor por el personaje aparece a su lado el engranaje que abre el
    /// detalle del agente (un clic en la figura lo abre en Claude; configurar no podía depender de un clic derecho).
    /// El engranaje cuelga fuera del nombre para que este no se descentre. Sin carpeta no hay qué gestionar.
    private func nameTag(_ seat: MesaSeat) -> some View {
        let anchor = Mesa.labelAnchor(seat.position, rise: rise(seat))
        let shown = hovered == seat.id
        return HStack(spacing: 5) {
            if model.opening == seat.id { LoadingRing(color: .ink900, size: 10) }
            Text(verbatim: seat.agent.name)
                .font(Typo.text(13.5, .medium))
                .foregroundStyle(seat.agent.folderExists ? Color.ink900 : Color.ink500)
                .underline(shown, color: .ink900)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay(alignment: .trailing) {
            if seat.agent.folderExists {
                Button {
                    onManage(seat.id)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.ink900)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.opening != nil)
                // Sigue ahí aunque no se vea: quien llega con el teclado o con VoiceOver también lo encuentra.
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: Motion.micro), value: shown)
                .onHover { inside in
                    if inside { hovered = seat.id } else if hovered == seat.id { hovered = nil }
                }
                .pointingHandOnHover(model.opening == nil)
                .help(Text(verbatim: Localized.string("home.table.manage %@", seat.agent.name, locale: locale)))
                .accessibilityLabel(Text(verbatim: Localized.string("home.table.manage %@", seat.agent.name, locale: locale)))
                .offset(x: 22)
            }
        }
        .frame(maxWidth: 108)
        .position(anchor)
    }

    private func hitArea(_ seat: MesaSeat) -> some View {
        let rect = Mesa.hitRect(seat.position, rise: rise(seat))
        return Button {
            if seat.agent.folderExists { model.open(seat.agent) } else { onShowCards() }
        } label: {
            Color.clear.frame(width: rect.width, height: rect.height).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.opening != nil)
        .onHover { inside in
            if inside { hovered = seat.id } else if hovered == seat.id { hovered = nil }
        }
        .pointingHandOnHover(model.opening == nil)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel(Text(verbatim: seat.agent.name + ", " + seat.agent.role.persona.name))
        .accessibilityHint(Text(seat.agent.folderExists ? "home.table.open.hint" : "home.table.missing"))
    }

    // MARK: El menú de un personaje

    /// Dónde se hizo el último clic derecho: ahí se despliega el menú.
    private func secondaryClick(at point: CGPoint) -> Bool {
        guard let seat = seats.first(where: { Mesa.hitRect($0.position, rise: rise($0)).contains(point) }),
            seat.agent.folderExists, model.opening == nil
        else {
            model.closeMenu()
            return false
        }
        menuAt = point
        model.showMenu(seat.agent)
        return true
    }

    /// El menú del clic derecho, con el oficio de la casa (el mismo de «Abrir en» de las tarjetas): papel, filete de
    /// tinta y renglones a filetes. Abrir en la app de Claude o en Terminal, y «Gestionar».
    private func seatMenu(_ seat: MesaSeat) -> some View {
        let rect = Mesa.hitRect(seat.position, rise: rise(seat))
        let wanted = menuAt ?? CGPoint(x: rect.maxX - 12, y: rect.minY + 26)
        let origin = CGPoint(
            x: min(max(wanted.x + 2, 4), Mesa.size.width - Self.menuWidth - 4),
            y: min(max(wanted.y + 2, 4), Mesa.size.height - Self.menuHeight - 4))
        return VStack(alignment: .leading, spacing: 0) {
            SmallCapsText(string: seat.agent.name, size: 11)
                .foregroundStyle(Color.ink500)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
            if model.canChoose {
                MenuOption(
                    title: "home.table.menu.app", detail: model.willRestartClaude(for: seat.agent) ? "home.menu.restart" : nil,
                    isCurrent: false, showsCheck: false
                ) { model.open(seat.agent, in: .app) }
                Rectangle().fill(Color.parchment300).frame(height: 1)
            }
            MenuOption(title: "home.table.menu.terminal", detail: nil, isCurrent: false, showsCheck: false) {
                model.open(seat.agent, in: .terminal)
            }
            Rectangle().fill(Color.parchment300).frame(height: 1)
            MenuOption(title: "home.manage", detail: nil, isCurrent: false, showsCheck: false) {
                model.closeMenu()
                onManage(seat.id)
            }
        }
        .frame(width: Self.menuWidth)
        .background(Color.parchment50)
        .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.b1))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(x: origin.x, y: origin.y)
    }

    private static let menuWidth: CGFloat = 214
    /// Lo que mide como mucho (título y tres renglones, uno con su nota): para que no se salga del lienzo por abajo.
    private static let menuHeight: CGFloat = 156

    /// De la séptima silla en adelante hay otra mesa: una flecha pequeña en cada esquina de abajo lleva a ella.
    private var pager: some View {
        HStack(spacing: 8) {
            if current > 0 { pageButton("chevron.left", "home.table.previous") { table = current - 1 } }
            Spacer(minLength: 0)
            Text(verbatim: Localized.string("home.table.page %lld %lld", current + 1, tables.count, locale: locale))
                .font(Typo.text(12.5))
                .foregroundStyle(Color.ink500)
            if current < tables.count - 1 { pageButton("chevron.right", "home.table.next") { table = current + 1 } }
        }
        .frame(width: Mesa.size.width - 8, height: 28)
        .position(x: Mesa.size.width / 2, y: Mesa.size.height - 16)
    }

    private func pageButton(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.ink900)
                .frame(width: 26, height: 26)
                .overlay(Rectangle().strokeBorder(Color.ink900, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .accessibilityLabel(Text(label))
    }

    // MARK: El renglón de abajo

    /// Lo que conviene saber del personaje bajo el cursor (o del que no se pudo abrir); si no, cómo se usa la mesa.
    @ViewBuilder
    private var caption: some View {
        if let failed = seats.first(where: { model.problems[$0.id] != nil }), let problem = model.problems[failed.id] {
            line(
                Text(verbatim: failed.agent.name + ": ").fontWeight(.semibold)
                    + Text(problem == .claudeDidNotQuit ? "done.open.claudeStillOpen" : "done.open.failed"),
                color: .ink900)
        } else if let seat = seats.first(where: { $0.id == hovered }) {
            if !seat.agent.folderExists {
                line(Text("home.table.missing"), color: .ink700)
            } else if model.effectiveTarget == .app, let reason = model.restartReason(for: seat.agent) {
                line(Text(reason == .connectors ? "done.open.restart" : "home.restart.toolsChanged"), color: .ink700)
            } else {
                line(Text(verbatim: summary(of: seat.agent)), color: .ink700)
            }
        } else {
            line(Text("home.table.hint"), color: .ink500)
        }
    }

    private func line(_ text: Text, color: Color) -> some View {
        text.font(Typo.text(13.5))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
    }

    /// «Galeno · Lee 4 herramientas · Con actividad reciente», y antes la descripción si la tiene.
    private func summary(of agent: HomeAgent) -> String {
        var parts = [agent.role.persona.name]
        if !agent.projectDescription.isEmpty { parts.append(agent.projectDescription) }
        let count = agent.tools.count
        if count == 0 {
            parts.append(text("home.reads.none"))
        } else {
            parts.append(Localized.string(count == 1 ? "home.reads.one" : "home.reads.other %lld", count, locale: locale))
        }
        if working.contains(agent.id) { parts.append(text("home.table.active")) }
        return parts.joined(separator: " · ")
    }

    private func text(_ key: String) -> String { Localized.string(key, locale: locale) }
}

/// La figura de un sitio: la lámina del personaje (con la mano moviéndose si escribe; en oscuro, algo apagada) o, si
/// no hay lámina o el agente no tiene carpeta, la figura de línea. Solo corre el reloj cuando una lámina escribe.
private struct FigureLayer: View {
    let seat: MesaSeat
    let plate: Bool
    let highlighted: Bool
    let writes: Bool
    let dimmed: Bool

    var body: some View {
        if plate {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !writes)) { timeline in
                let hand =
                    writes
                    ? Mesa.writingOffset(time: timeline.date.timeIntervalSinceReferenceDate, position: seat.position) : .zero
                Canvas { context, _ in
                    MesaDrawing.plate(
                        &context, persona: seat.agent.role.persona, position: seat.position, hand: hand, dimmed: dimmed)
                }
            }
            .allowsHitTesting(false)
        } else {
            Canvas { context, _ in
                MesaDrawing.figure(
                    &context, role: seat.agent.role, frame: .init(position: seat.position), highlighted: highlighted,
                    missing: !seat.agent.folderExists, dark: seat.alternate)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Lo que hay sobre el tablero delante de un sitio: su objeto y, para la figura de línea, el papel y el brazo con la
/// pluma (una lámina trae los suyos). Solo corre el reloj cuando una figura de línea escribe.
private struct DeskLayer: View {
    let seat: MesaSeat
    let plate: Bool
    let highlighted: Bool
    let writes: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !writes || plate)) { timeline in
            let hand =
                writes && !plate
                ? Mesa.writingOffset(time: timeline.date.timeIntervalSinceReferenceDate, position: seat.position) : .zero
            Canvas { context, _ in
                MesaDrawing.desk(
                    &context, position: seat.position, frame: .init(position: seat.position), hand: hand,
                    highlighted: highlighted, dark: seat.alternate, writes: !plate)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Avisa de los clics derechos (o con Control) dentro de la vista que lo lleva de fondo, con el punto en sus
/// coordenadas (origen arriba a la izquierda). No es un control: no recibe clics ni tapa nada (`hitTest` es `nil`);
/// solo escucha los del ratón de su ventana. Si quien lo usa dice que atendió el clic, el evento se queda ahí.
private struct SecondaryClickMonitor: NSViewRepresentable {
    let onClick: (CGPoint) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) { view.onClick = onClick }

    final class MonitorView: NSView {
        var onClick: ((CGPoint) -> Bool)?
        private var monitor: Any?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                    event.type == .rightMouseDown || event.modifierFlags.contains(.control)
                else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                return self.onClick?(point) == true ? nil : event
            }
        }
    }
}
