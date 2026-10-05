import GalenoCore
import SwiftUI

// MARK: - El resultado de una skill, como documento

/// Un trozo del resultado de ejemplo de una skill. El catálogo lo escribe como líneas con una marca al principio
/// (`SkillExample.output`), para que el ejemplo se vea **con la forma de lo que esa skill entrega**: un acta con
/// secciones, un roadmap en tabla, un borrador para Slack.
enum SkillDocBlock: Equatable {
    /// `# Acta · reunión con el cliente`
    case title(String)
    /// `## Decisiones`
    case section(String)
    /// `- Se pospone el rediseño del login.`
    case bullet(String)
    /// `> Esta semana: …` — un mensaje en borrador (lo que saldría a Slack o a una persona).
    case quote(String)
    /// `| Épica | Trimestre |` — las filas seguidas forman una tabla; la primera es el encabezado.
    case table([[String]])
    case paragraph(String)
}

enum SkillDoc {
    /// Las líneas del catálogo, como bloques. Es lógica pura: se prueba sin vistas.
    static func blocks(_ lines: [String]) -> [SkillDocBlock] {
        var blocks: [SkillDocBlock] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("|") {
                let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .dropFirst().dropLast(line.hasSuffix("|") ? 1 : 0)
                let row = Array(cells)
                if case .table(var rows)? = blocks.last {
                    rows.append(row)
                    blocks[blocks.count - 1] = .table(rows)
                } else {
                    blocks.append(.table([row]))
                }
            } else if line.hasPrefix("## ") {
                blocks.append(.section(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") {
                blocks.append(.quote(String(line.dropFirst(2))))
            } else {
                blocks.append(.paragraph(line))
            }
        }
        return blocks
    }

    /// El documento como texto corrido, para VoiceOver.
    static func plainText(_ lines: [String]) -> String {
        blocks(lines).map { block -> String in
            switch block {
            case .title(let text), .section(let text), .bullet(let text), .quote(let text), .paragraph(let text): text
            case .table(let rows): rows.map { $0.joined(separator: ", ") }.joined(separator: ". ")
            }
        }.joined(separator: ". ")
    }
}

/// Pinta los bloques con la tipografía de B1: título en Cormorant, secciones en versalitas, tabla a filetes.
struct SkillDocView: View {
    let blocks: [SkillDocBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: SkillDocBlock) -> some View {
        switch block {
        case .title(let text):
            Text(verbatim: text).font(Typo.display(17)).foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
        case .section(let text):
            SmallCapsText(string: text, size: 11, tracking: 0.1).foregroundStyle(Color.ink500)
                .padding(.top, 3)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "·").foregroundStyle(Color.ink500)
                Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
            }
            .font(Typo.text(13.5)).foregroundStyle(Color.ink900)
        case .quote(let text):
            Text(verbatim: text)
                .font(Typo.text(13.5)).foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 9)
                .overlay(alignment: .leading) { Rectangle().fill(Color.ink500).frame(width: 2) }
        case .paragraph(let text):
            Text(verbatim: text).font(Typo.text(13.5)).foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
        case .table(let rows):
            table(rows)
        }
    }

    /// Una tabla sobria: encabezado en versalitas, un filete entre filas, sin rejilla vertical.
    private func table(_ rows: [[String]]) -> some View {
        let columns = rows.map(\.count).max() ?? 0
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let text = column < row.count ? row[column] : ""
                        Group {
                            if index == 0 {
                                SmallCapsText(string: text, size: 11, tracking: 0.08).foregroundStyle(Color.ink500)
                            } else {
                                Text(verbatim: text).font(Typo.text(13)).foregroundStyle(Color.ink900)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                if index < rows.count - 1 {
                    Rectangle().fill(index == 0 ? Color.ink500 : Color.parchment300).frame(height: 1)
                        .gridCellColumns(max(columns, 1))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - La demostración

/// Los tiempos de la demostración. Lógica pura.
enum SkillDemoTiming {
    /// Cuánto tarda cada letra: 35 ms, pero una pregunta larga nunca pasa de 1,6 s en total.
    static func perCharacter(count: Int) -> Duration {
        guard count > 0 else { return .zero }
        return .milliseconds(min(35, 1600 / count))
    }
    static let beforeSending: Duration = .milliseconds(350)
    static let beforeThinking: Duration = .milliseconds(250)
    static let thinking: Duration = .milliseconds(1400)
    static let betweenBlocks: Duration = .milliseconds(180)
}

/// Cómo se ve usar una skill (decisión de Rafa, 5 oct 2026): la pregunta se escribe sola, se envía, el agente
/// «piensa» y aparece el resultado con la forma de lo que esa skill entrega.
///
/// **Es una ilustración**: los textos vienen del catálogo, no se llama a ningún modelo ni se gasta cuota, y la hoja lo
/// dice debajo. Quien responde lleva el nombre del agente del usuario; no se usa la marca de Claude. Con «Menos
/// movimiento» se muestra el resultado final, sin animar.
struct SkillDemoView: View {
    let skill: CatalogSkill
    let example: SkillExample
    let language: Language
    /// El nombre del agente («Hera»), o el genérico si todavía no tiene.
    let agentName: String
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    enum Phase: Equatable {
        /// Escribiendo: cuántas letras van.
        case typing(Int)
        /// Enviado: la pregunta sube a la conversación.
        case sent
        case thinking
        /// Respondiendo: cuántos bloques del resultado se ven.
        case answering(Int)
        case done
    }

    @State private var phase: Phase = .typing(0)

    /// Lo que el usuario escribiría: la frase natural, o el comando si la skill no trae una.
    private var question: String {
        let ask = skill.ask?.text(in: language) ?? ""
        return ask.isEmpty ? skill.command : ask
    }
    private var blocks: [SkillDocBlock] { SkillDoc.blocks(example.output.lines(in: language)) }

    private var typed: String {
        if case .typing(let count) = phase { return String(question.prefix(count)) }
        return ""
    }
    private var questionWasSent: Bool {
        if case .typing = phase { return false }
        return true
    }
    private var visibleBlocks: [SkillDocBlock] {
        switch phase {
        case .answering(let count): Array(blocks.prefix(count))
        case .done: blocks
        default: []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            conversation
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Color.parchment300).frame(height: 1)
            inputBar
        }
        .background(Color.parchment100)
        .overlay(Rectangle().strokeBorder(Color.parchment300, lineWidth: 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: phase)
        .task(id: skill.id) { await play() }
        // VoiceOver lee la conversación entera de una vez, sin esperar a la animación.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(question). \(agentName): \(SkillDoc.plainText(example.output.lines(in: language)))"))
    }

    /// La conversación: la pregunta del usuario a la derecha y, debajo, lo que hace el agente.
    private var conversation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if questionWasSent {
                    HStack {
                        Spacer(minLength: 60)
                        Text(verbatim: question)
                            .font(Typo.text(13.5))
                            .foregroundStyle(Color.ink900)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.parchment200)
                            .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
                }
                if phase == .thinking {
                    HStack(spacing: 8) {
                        InkSpinner(size: 12)
                        Text(verbatim: Localized.string("skills.demo.reads %@ %@", agentName, example.input.text(in: language), locale: locale))
                            .font(Typo.text(13, italic: true))
                            .foregroundStyle(Color.ink500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }
                if !visibleBlocks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SmallCapsText(string: agentName, size: 11, tracking: 0.1).foregroundStyle(Color.ink500)
                        SkillDocView(blocks: visibleBlocks)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.top)
    }

    /// El campo donde se escribe la pregunta y el botón de enviar. No son controles de verdad: nada de esto se envía.
    private var inputBar: some View {
        let isTyping = !typed.isEmpty
        return HStack(spacing: 8) {
            Group {
                if isTyping {
                    HStack(spacing: 1) {
                        Text(verbatim: typed).foregroundStyle(Color.ink900).lineLimit(1).truncationMode(.head)
                        Rectangle().fill(Color.ink900).frame(width: 1, height: 15)
                    }
                } else {
                    Text(verbatim: Localized.string("skills.demo.placeholder %@", agentName, locale: locale))
                        .foregroundStyle(Color.ink500)
                        .lineLimit(1)
                }
            }
            .font(Typo.text(13.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isTyping ? Color.onInk : Color.ink500)
                .frame(width: 22, height: 22)
                .background(isTyping ? Color.ink900 : Color.clear)
                .overlay(Rectangle().strokeBorder(isTyping ? Color.ink900 : Color.parchment400, lineWidth: 1.5))
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Color.parchment50)
        .accessibilityHidden(true)
    }

    /// La secuencia. Se corta sola si la vista desaparece o se pide verla de nuevo (la tarea se cancela).
    private func play() async {
        guard !reduceMotion else {
            phase = .done
            return
        }
        phase = .typing(0)
        func pause(_ duration: Duration) async -> Bool {
            (try? await Task.sleep(for: duration)) != nil && !Task.isCancelled
        }
        guard await pause(.milliseconds(350)) else { return }
        let perCharacter = SkillDemoTiming.perCharacter(count: question.count)
        for count in 1...max(question.count, 1) {
            guard await pause(perCharacter) else { return }
            phase = .typing(count)
        }
        guard await pause(SkillDemoTiming.beforeSending) else { return }
        phase = .sent
        guard await pause(SkillDemoTiming.beforeThinking) else { return }
        phase = .thinking
        guard await pause(SkillDemoTiming.thinking) else { return }
        for count in 1...max(blocks.count, 1) {
            phase = .answering(count)
            guard await pause(SkillDemoTiming.betweenBlocks) else { return }
        }
        phase = .done
    }
}
