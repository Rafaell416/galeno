import SwiftUI

/// Qué se ve de una lista de frases cuando han pasado `elapsed` segundos: cuál toca y cuántas letras lleva
/// escritas. Es una función del tiempo y nada más, para poder probarla y para que la vista no guarde estado.
nonisolated enum WaitingScript {
    /// Letras por segundo: se lee mientras se escribe.
    static let charactersPerSecond = 42.0

    struct Frame: Equatable {
        var index: Int
        var visible: Int
        /// La frase ya está entera (lo que queda del turno es para leerla).
        var isComplete: Bool
    }

    /// Las frases salen en orden, cada una `interval` segundos. Al acabar la lista no se vuelve a la primera
    /// (que suele decir qué se está haciendo): se repiten las de `loopFrom` en adelante.
    static func frame(elapsed: TimeInterval, lines: [String], interval: TimeInterval, loopFrom: Int = 0) -> Frame {
        guard !lines.isEmpty, interval > 0 else { return Frame(index: 0, visible: 0, isComplete: true) }
        let time = max(0, elapsed)
        let turn = Int(time / interval)
        let index: Int
        if turn < lines.count {
            index = turn
        } else {
            let start = min(max(0, loopFrom), lines.count - 1)
            index = start + (turn - lines.count) % (lines.count - start)
        }
        let typed = Int((time - Double(turn) * interval) * charactersPerSecond)
        let count = lines[index].count
        return Frame(index: index, visible: min(count, typed), isComplete: typed >= count)
    }

    /// «0:07», «1:42»: cuánto lleva.
    static func clock(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// Lo que se lee mientras algo tarda (instalar Claude Code, esperar al navegador): una frase que se escribe
/// sola, con su cursor, y cambia cada pocos segundos; debajo, un filete con un trazo que va y viene, y el
/// tiempo que lleva. En lugar de una rueda girando sin decir nada.
///
/// Las frases **no fingen un progreso que Galeno no conoce**: dicen cosas ciertas pase lo que pase (qué se
/// descarga, cuánto suele tardar, qué hará y qué no hará el agente). Pasado `slowAfter`, se añade una línea
/// que reconoce la demora.
struct WaitingTicker: View {
    /// Ya traducidas.
    let lines: [String]
    var interval: TimeInterval = 5.5
    /// Desde cuál se repite al acabar la lista.
    var loopFrom = 0
    /// La línea que aparece si esto tarda más de lo normal, y cuándo.
    var slowLine: String?
    var slowAfter: TimeInterval = 90

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.periodic(from: start, by: reduceMotion ? 1 : 1.0 / 30)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let frame = WaitingScript.frame(elapsed: elapsed, lines: lines, interval: interval, loopFrom: loopFrom)
            let line = lines.isEmpty ? "" : lines[frame.index]
            VStack(alignment: .leading, spacing: 12) {
                // La frase entera reserva su sitio (invisible): el renglón no salta mientras se escribe.
                Text(verbatim: line)
                    .hidden()
                    .overlay(alignment: .topLeading) {
                        (Text(verbatim: reduceMotion ? line : String(line.prefix(frame.visible)))
                            + Text(verbatim: reduceMotion || (frame.isComplete && Int(elapsed * 2) % 2 == 0) ? "" : "▏")
                            .foregroundColor(Color.ink500))
                    }
                    .font(Typo.display(19, italic: true))
                    .foregroundStyle(Color.ink700)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(verbatim: line))

                HStack(spacing: 14) {
                    SweepRule(elapsed: elapsed, isStill: reduceMotion)
                    Text(verbatim: WaitingScript.clock(elapsed))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ink500)
                        .accessibilityHidden(true)
                }

                if let slowLine, elapsed >= slowAfter {
                    Text(verbatim: slowLine)
                        .font(Typo.text(13.5))
                        .foregroundStyle(Color.ochre700)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
        }
    }
}

/// Un filete de 1 pt con un trazo de 3 pt en tinta que va y viene: «sigue en marcha», sin prometer cuánto falta.
private struct SweepRule: View {
    let elapsed: TimeInterval
    var isStill = false

    private static let period = 2.4
    private static let share: CGFloat = 0.22

    var body: some View {
        GeometryReader { proxy in
            // Ida y vuelta, frenando en los extremos.
            let phase = elapsed.truncatingRemainder(dividingBy: Self.period) / Self.period
            let position = isStill ? 0 : CGFloat(0.5 - 0.5 * cos(phase * 2 * .pi))
            let width = proxy.size.width * Self.share
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.parchment300).frame(height: 1)
                Rectangle().fill(Color.ink900).frame(width: width, height: 3)
                    .offset(x: (proxy.size.width - width) * position)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
