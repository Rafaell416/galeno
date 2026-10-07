import AppKit
import GalenoCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Piezas comunes

/// Un renglón de lista a filetes: rótulo en versalitas, valor y, a la derecha, una acción. El fondo de cada fila es un
/// filete fino; la lista lleva uno grueso de tinta arriba (`AgentList`).
private struct DetailRow<Content: View, Trailing: View>: View {
    let label: String
    var labelWidth: CGFloat = 130
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SmallCapsLabel(label, size: 12, tracking: 0.12)
                .foregroundStyle(Color.ink500)
                .frame(width: labelWidth, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
    }
}

/// La lista: un filete de tinta de 1 pt arriba y las filas debajo.
private struct AgentList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.ink900).frame(height: 1)
            content
        }
    }
}

/// Un enlace de acción leve y reversible («Renombrar», «Quitar»): texto subrayado en tinta.
private struct LeadLink: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action).buttonStyle(InkLinkStyle(size: 14.5)).lineLimit(1)
    }
}

/// `~` en lugar de la ruta completa del usuario.
private func abbreviatedPath(_ url: URL) -> String {
    let home = NSHomeDirectory()
    return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
}

// MARK: - General

/// Nombre, rol, carpeta, dónde se abre y, aparte, eliminar. «Eliminar» vive abajo, en un recuadro propio: nunca en la
/// cabecera.
struct GeneralSection: View {
    @ObservedObject var model: AgentDetailModel
    @Environment(\.locale) private var locale

    private var roleBinding: Binding<AgentRole> {
        Binding(get: { model.role }, set: { model.setRole($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentList {
                DetailRow(label: "agent.general.name") {
                    Text(verbatim: model.name).font(Typo.text(17)).foregroundStyle(Color.ink900)
                } trailing: {
                    LeadLink("agent.general.rename") { model.askRename() }
                }
                DetailRow(label: "agent.general.role") {
                    VStack(alignment: .leading, spacing: 6) {
                        InkSegmented(selection: roleBinding, options: AgentRole.allCases, padding: 14, fontSize: 14.5) { role in
                            Text(verbatim: role.title(in: model.language))
                        }
                        .disabled(model.isWorking)
                        Text("agent.general.role.note").font(Typo.text(13)).foregroundStyle(Color.ink500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } trailing: { EmptyView() }
                DetailRow(label: "agent.general.folder") {
                    Text(verbatim: model.folder.map(abbreviatedPath) ?? "")
                        .font(.system(size: 13.5, design: .monospaced)).foregroundStyle(Color.ink700)
                        .lineLimit(1).truncationMode(.middle)
                } trailing: {
                    LeadLink("agent.general.reveal") { model.revealFolder() }
                }
                DetailRow(label: "agent.general.openIn") {
                    Text(LocalizedStringKey(model.home.effectiveTarget == .app ? "home.target.app" : "home.target.terminal"))
                        .font(Typo.text(17)).foregroundStyle(Color.ink900)
                } trailing: {
                    if model.home.canChoose {
                        LeadLink(model.home.effectiveTarget == .app ? "agent.general.switch.terminal" : "agent.general.switch.app") {
                            model.home.setOpenTarget(model.home.effectiveTarget == .app ? .terminal : .app)
                        }
                    }
                }
                if let created = model.createdAt {
                    DetailRow(label: "agent.general.created") {
                        Text(created, format: Date.FormatStyle(date: .long, time: .omitted).locale(locale))
                            .font(Typo.text(17)).foregroundStyle(Color.ink900)
                    } trailing: { EmptyView() }
                }
            }
            danger
        }
    }

    /// El recuadro de eliminar: aparte y sin prisa.
    private var danger: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: Localized.string("agent.delete.title %@", model.name, locale: locale))
                    .font(Typo.text(16, .medium)).foregroundStyle(Color.ink900)
                Text("agent.delete.hint").font(Typo.text(14)).foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("agent.delete.button") { model.askDelete() }
                .buttonStyle(.inkInline)
                .disabled(model.isWorking || model.agent == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
        .padding(.top, 26)
    }
}

// MARK: - Herramientas

/// Lo que el agente lee, con su estado y una acción por herramienta: reconectar, quitar, y añadir las que faltan. La
/// espera es por fila y nunca se marca sola (es el mismo `HealthModel` de Salud).
struct ToolsSection: View {
    @ObservedObject var model: AgentDetailModel
    @State private var addOpen = false
    @Environment(\.galenoReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.toolRows.isEmpty {
                Text("agent.tools.none").font(Typo.text(15)).foregroundStyle(Color.ink500)
            } else {
                AgentList {
                    ForEach(model.toolRows) { row in
                        ToolRowView(model: model, row: row)
                            // La que acaba de conectarse entra desde abajo, con un destello (`justAdded`).
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: model.toolRows.map(\.tool))
            }
            if !model.addableTools.isEmpty { addArea.padding(.top, 14) }
        }
        .animation(.easeOut(duration: Motion.micro), value: addOpen)
    }

    @ViewBuilder
    private var addArea: some View {
        if addOpen {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SmallCapsLabel("agent.tools.add", size: 12, tracking: 0.12).foregroundStyle(Color.ink500)
                    Spacer(minLength: 8)
                    Button("wizard.cancel") { addOpen = false }.buttonStyle(InkLinkStyle(size: 14))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(model.addableTools) { tool in
                        AddToolButton(tool: tool, language: model.language, isDisabled: model.isPreparingConnection || model.isWorking) {
                            addOpen = false
                            Task { await model.startConnecting(tool) }
                        }
                    }
                }
                Text("agent.tools.add.hint").font(Typo.text(13)).foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(Rectangle().strokeBorder(Color.ink900, lineWidth: 1.5))
            .transition(.opacity)
        } else {
            Button { addOpen = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("agent.tools.add")
                }
                .font(Typo.text(15, .medium))
                .foregroundStyle(Color.ink700)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .overlay(Rectangle().strokeBorder(Color.parchment400, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            .disabled(model.isWorking)
        }
    }
}

private struct AddToolButton: View {
    let tool: Tool
    let language: Language
    var isDisabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ToolIcon(tool: tool, size: 20, color: .ink700)
                Text(verbatim: tool.displayName(in: language)).font(Typo.text(15, .medium)).foregroundStyle(Color.ink900)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(hovering ? Color.parchment100 : Color.clear)
            .overlay(Rectangle().strokeBorder(hovering ? Color.ink900 : Color.parchment400, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering = $0 }
        .pointingHandOnHover()
    }
}

private struct ToolRowView: View {
    @ObservedObject var model: AgentDetailModel
    let row: AgentDetailModel.ToolRow
    @Environment(\.locale) private var locale

    private var isReconnecting: Bool { model.health.reconnecting == row.tool }
    private var health: HealthModel { model.health }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 14) {
                ToolIcon(tool: row.tool, size: 24, color: .ink700).frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.tool.displayName(in: model.language))
                        .font(Typo.text(17, .medium)).foregroundStyle(Color.ink900)
                    Text(verbatim: stateText).font(Typo.text(14)).foregroundStyle(stateColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if isChecking { InkSpinner(size: 14) }
                LeadLink("agent.tools.remove") { model.askRemove(row.tool) }
                    .disabled(model.isWorking || isReconnecting)
                action
            }
            if let issue = health.reconnectIssues[row.tool] {
                Text(verbatim: Localized.string(issue.messageKey, locale: locale))
                    .font(Typo.text(13)).foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 42)
            }
        }
        .padding(.vertical, 12)
        // El destello de la herramienta que se acaba de conectar.
        .background(model.justAdded == row.tool ? Color.moss100 : Color.clear)
        .animation(.easeOut(duration: 0.8), value: model.justAdded)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private var isChecking: Bool {
        switch row.status {
        case .hosted(.checking), .whatsappChecking: true
        default: false
        }
    }

    /// La acción fuerte, si hace falta: «Reconectar» una herramienta o «Vincular» / «Re-vincular» WhatsApp.
    @ViewBuilder
    private var action: some View {
        switch row.status {
        case .hosted(let state) where state.canReconnect && row.canReconnect:
            Button("health.reconnect") { model.reconnect(row.tool) }
                .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 14, isLoading: isReconnecting))
                .disabled(health.reconnecting != nil || model.isWorking)
        case .whatsappNotLinked:
            Button("health.whatsapp.link") { model.relinkWhatsApp() }
                .buttonStyle(.inkInline)
                .disabled(health.relink != .idle)
        case .whatsappLinked(_, let rotate) where rotate:
            Button("health.whatsapp.relink") { model.relinkWhatsApp() }
                .buttonStyle(.inkInline)
                .disabled(health.relink != .idle)
        default:
            EmptyView()
        }
    }

    /// Una línea: lo que se sabe, y de quién más es. Lo que no se pudo averiguar se dice («Sin saber»), nunca «Conectada».
    private var stateText: String {
        var text: String
        switch row.status {
        case .hosted(let state): text = Localized.string(Self.key(for: state), locale: locale)
        case .whatsappChecking: text = Localized.string("health.state.checking", locale: locale)
        case .whatsappNoAnswer: text = Localized.string("agent.tools.whatsapp.noAnswer", locale: locale)
        case .whatsappNotLinked: text = Localized.string("health.whatsapp.notLinked", locale: locale)
        case .whatsappLinked(let days, let rotate):
            if rotate, let days {
                text = Localized.string("agent.tools.whatsapp.rotate %lld", days, locale: locale)
            } else {
                text = Localized.string("health.whatsapp.linked", locale: locale)
                if let days { text += " · " + daysText(days) }
            }
        }
        if !row.sharedWith.isEmpty, case .hosted(.connected) = row.status {
            text += " · " + Localized.string("agent.tools.shared %@", row.sharedWith.joined(separator: ", "), locale: locale)
        }
        return text
    }

    private var stateColor: Color {
        switch row.status {
        case .hosted(let state):
            switch state {
            case .connected: .moss700
            case .needsAuthorization, .failed, .missing: .ochre700
            case .checking, .pending, .unknown: .ink500
            }
        case .whatsappLinked(_, let rotate): rotate ? .ochre700 : .moss700
        case .whatsappNotLinked: .ochre700
        case .whatsappChecking, .whatsappNoAnswer: .ink500
        }
    }

    private static func key(for state: HealthModel.ConnectionState) -> String {
        switch state {
        case .checking: "health.state.checking"
        case .connected: "health.state.connected"
        case .pending: "health.state.pending"
        case .needsAuthorization: "health.state.needsAuthorization"
        case .failed: "health.state.failed"
        case .missing: "health.state.missing"
        case .unknown: "health.state.unknown"
        }
    }

    private func daysText(_ days: Int) -> String {
        switch days {
        case 0: Localized.string("health.whatsapp.days.today", locale: locale)
        case 1: Localized.string("health.whatsapp.days.one", locale: locale)
        default: Localized.string("health.whatsapp.days.other %lld", days, locale: locale)
        }
    }
}

extension HealthModel.ReconnectIssue {
    /// La clave del texto que explica por qué no se pudo reconectar.
    var messageKey: String {
        switch self {
        case .needsWizard: "health.reconnect.issue.needsWizard"
        case .notAuthorized: "health.reconnect.issue.notAuthorized"
        case .timedOut: "health.reconnect.issue.timedOut"
        case .stillNotConnected: "health.reconnect.issue.stillNotConnected"
        case .nameTaken: "health.reconnect.issue.nameTaken"
        case .claudeOutdated: "health.reconnect.issue.claudeOutdated"
        case .failed: "health.reconnect.issue.failed"
        }
    }
}

// MARK: - Skills

/// Las cards de siempre —las de las skills del rol, «Tus skills» y «Añadir skill…»— para marcar y desmarcar aquí mismo, con su
/// «Guardar skills». El catálogo es el del asistente (`SkillsStepView`, en su versión embebida); lo marcado se guarda al
/// pulsar «Guardar», no al marcar.
struct SkillsEditor: View {
    @ObservedObject var model: AgentDetailModel

    var body: some View {
        Group {
            if let picker = model.picker {
                VStack(spacing: 0) {
                    SkillsStepView(embedded: true)
                        .environmentObject(picker)
                    Rectangle().fill(Color.parchment300).frame(height: 1)
                    HStack(alignment: .center, spacing: 12) {
                        Text(LocalizedStringKey(model.skillsDirty ? "agent.skills.unsaved" : "agent.skills.hint"))
                            .font(Typo.text(13))
                            .foregroundStyle(model.skillsDirty ? Color.ochre700 : Color.ink500)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("agent.skills.discard") { model.discardSkillChanges() }
                            .buttonStyle(InkLinkStyle(size: 14.5))
                            .disabled(!model.skillsDirty || model.isWorking)
                        Button("agent.skills.save") { model.saveSkills() }
                            .buttonStyle(InkButtonStyle(.primary, size: .bar, padding: 18, isLoading: model.isWorking))
                            .disabled(!model.skillsDirty || model.isWorking)
                    }
                    .padding(.top, 10)
                }
            } else {
                InkSpinner(size: 16).padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.prepareSkillsEditor() }
    }
}

// MARK: - Reglas

/// Lo que el agente nunca hace, lo que siempre pregunta y lo que puede decidirse; lo elegible aplica **al momento**.
struct RulesSection: View {
    @ObservedObject var model: AgentDetailModel
    @Environment(\.locale) private var locale

    private var tools: [Tool] { model.config?.connectedTools ?? [] }
    private var externalTools: [Tool] {
        (model.config?.connectedConnections ?? []).filter(\.sendsToOthers).map(\.tool)
    }
    private var readsFreely: [Tool] { model.config?.toolsReadingWithoutAsking ?? [] }
    /// WhatsApp conectado sin el envío aceptado: ese agente solo lo lee.
    private var whatsAppIsReadOnly: Bool {
        (model.config?.connectedConnections ?? []).contains { $0.tool == .whatsapp && !$0.sendsToOthers }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentList {
                fixedRow(
                    title: "rules.external.title", body: Text("rules.external.body"),
                    detail: externalTools.isEmpty ? nil : Localized.string(
                        "rules.external.tools %@", externalTools.map { $0.displayName(in: model.language) }.joined(separator: ", "),
                        locale: locale))
                if whatsAppIsReadOnly {
                    fixedRow(
                        title: "rules.never.title", body: Text("rules.never.body \(model.name)"), detail: nil)
                }
                if !readsFreely.isEmpty {
                    fixedRow(
                        title: "rules.reads.title", body: Text("rules.reads.body \(model.name)"),
                        detail: Localized.string(
                            "rules.external.tools %@", readsFreely.map { $0.displayName(in: model.language) }.joined(separator: ", "),
                            locale: locale),
                        locked: false)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                let writes = model.configurableWrites
                SmallCapsLabel("agent.rules.write.heading", size: 12, tracking: 0.12)
                    .foregroundStyle(Color.ink500)
                    .padding(.top, 22)
                    .padding(.bottom, 6)
                Text(writes.isEmpty ? "rules.none" : "rules.internal.hint")
                    .font(Typo.text(14)).foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                if !writes.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(writes, id: \.self) { write in
                            WriteRuleRow(
                                write: write, agentName: model.name, policy: model.policy(for: write),
                                onChange: { model.setPolicy($0, for: write) })
                            .disabled(model.isWorking)
                        }
                    }
                    .padding(.top, 12)
                }
            }
            Text(verbatim: Localized.string("agent.rules.note %@", model.name, locale: locale))
                .font(Typo.text(13)).foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    /// Una regla que no se cambia: con el candado de «Fija», o sin él si es lo que no pregunta.
    private func fixedRow(title: LocalizedStringKey, body: Text, detail: String?, locked: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ActIcon(name: locked ? "lock" : "ask", size: 22, color: .ink700)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                (Text(title).font(Typo.text(15.5, .semibold)) + Text(verbatim: ". ").font(Typo.text(15.5, .semibold))
                    + body.font(Typo.text(15.5)))
                    .foregroundStyle(Color.ink900)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(verbatim: detail).font(Typo.text(13)).foregroundStyle(Color.ink500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if locked {
                SmallCapsLabel("agent.rules.fixed", size: 12, tracking: 0.12).foregroundStyle(Color.ink700)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
    }
}

// MARK: - Contexto

/// La línea del proyecto y los materiales que el agente lee, con «Quitar»; todo se aplica con «Guardar contexto».
struct ContextSection: View {
    @ObservedObject var model: AgentDetailModel
    @Environment(\.locale) private var locale
    @State private var dropTargeted = false
    @State private var hoveringDrop = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            projectField
            filesField
            HStack(alignment: .center, spacing: 16) {
                Button("agent.context.save") { model.saveContext() }
                    .buttonStyle(InkButtonStyle(.primary, size: .regular, padding: 22, isLoading: model.isWorking))
                    .disabled(!model.hasUnsavedContext || model.isWorking)
                Text(verbatim: Localized.string(
                    model.hasUnsavedContext ? "agent.context.unsaved" : "agent.context.saved %@", model.name, locale: locale))
                    .font(Typo.text(14)).foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: El proyecto

    private var counterColor: Color {
        let count = model.projectDraft.count
        if count >= WizardState.maxProjectDescriptionLength { return .seal700 }
        return count >= 120 ? .ochre700 : .ink500
    }

    private var projectField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SmallCapsLabel("context.project.label", size: 12, tracking: 0.12).foregroundStyle(Color.ink500)
                Spacer()
                Text(verbatim: "\(model.projectDraft.count)/\(WizardState.maxProjectDescriptionLength)")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(counterColor)
                    .opacity(model.projectDraft.isEmpty ? 0 : 1)
            }
            .padding(.bottom, 4)
            RuleTextField(
                "context.project.label", text: $model.projectDraft, prompt: "context.project.placeholder",
                font: Typo.text(17), lines: 2
            )
            .onChange(of: model.projectDraft) { _, text in
                if text.count > WizardState.maxProjectDescriptionLength {
                    model.projectDraft = String(text.prefix(WizardState.maxProjectDescriptionLength))
                }
            }
        }
    }

    // MARK: Los archivos

    private var filesField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SmallCapsText(
                    string: Localized.string("agent.context.files %lld", model.contextEntries.count - model.removedContext.count + model.pendingContext.count, locale: locale),
                    size: 12, tracking: 0.12)
                    .foregroundStyle(Color.ink500)
                Spacer()
                Text("agent.context.limit").font(Typo.text(13)).foregroundStyle(Color.ink500)
            }
            AgentList {
                ForEach(model.contextEntries) { entry in entryRow(entry) }
                ForEach(Array(model.pendingContext.enumerated()), id: \.offset) { _, file in pendingRow(file) }
                if model.contextEntries.isEmpty, model.pendingContext.isEmpty {
                    Text("agent.context.empty").font(Typo.text(14)).foregroundStyle(Color.ink500)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
                }
            }
            .padding(.top, 8)

            Button(action: pickFiles) {
                (Text("context.files.drop") + Text(verbatim: " ")
                    + Text("context.files.pick").underline().foregroundColor(Color.ink900))
                    .font(Typo.text(15)).foregroundStyle(Color.ink700)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(dropTargeted || hoveringDrop ? Color.parchment100 : Color.clear)
                    .overlay(
                        Rectangle().strokeBorder(
                            dropTargeted ? Color.ink900 : Color.parchment400,
                            style: StrokeStyle(lineWidth: dropTargeted ? 1.5 : 1, dash: dropTargeted ? [] : [4, 3])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringDrop = $0 }
            .pointingHandOnHover()
            .disabled(model.contextSlotsLeft == 0)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in model.addContext(from: url) }
                    }
                }
                return true
            }
            .padding(.top, 10)

            if let problem = model.contextProblem {
                Text(LocalizedStringKey(Self.key(for: problem))).font(Typo.text(13)).foregroundStyle(Color.seal700)
                    .padding(.top, 8)
            }
            Text("context.files.note").font(Typo.text(13)).foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private func entryRow(_ entry: ContextEntry) -> some View {
        let removed = model.removedContext.contains(entry.fileName)
        return HStack(spacing: 14) {
            Text(verbatim: entry.title).font(Typo.text(15)).lineLimit(1).truncationMode(.middle)
                .strikethrough(removed)
                .foregroundStyle(removed ? Color.ink500 : Color.ink900)
            Text(verbatim: Self.size(entry.bytes)).font(Typo.text(13)).foregroundStyle(Color.ink500)
            Spacer(minLength: 8)
            if removed { Text("agent.context.willRemove").font(Typo.text(13)).foregroundStyle(Color.ink500) }
            LeadLink(removed ? "agent.context.undo" : "context.remove") { model.toggleRemoveContext(entry) }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
    }

    private func pendingRow(_ file: ContextFile) -> some View {
        HStack(spacing: 14) {
            TracedShape(shape: CheckMark(), lineWidth: 1.5, color: .moss700, duration: 0.18)
                .frame(width: 14, height: 14).accessibilityHidden(true)
            Text(verbatim: file.title).font(Typo.text(15)).lineLimit(1).truncationMode(.middle).foregroundStyle(Color.ink900)
            Text("context.item.size \(file.text.count)").font(Typo.text(13)).foregroundStyle(Color.ink500)
            Spacer(minLength: 8)
            Text("agent.context.new").font(Typo.text(13)).foregroundStyle(Color.moss700)
            LeadLink("context.remove") { model.removePendingContext(file) }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ContextImporter.allowedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { model.addContext(from: $0) }
    }

    private static func key(for problem: AgentDetailModel.ContextProblem) -> String {
        switch problem {
        case .unsupported: "context.error.unsupported"
        case .tooLarge: "context.error.tooLarge"
        case .unreadable: "context.error.unreadable"
        case .tooMany: "context.error.tooMany"
        case .tooLong: "context.error.tooLong"
        case .empty: "context.error.empty"
        }
    }

    /// «1,2 MB», «240 KB».
    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
