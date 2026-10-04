import GalenoCore
import SwiftUI

/// Paso 6: qué lee el agente de cada herramienta (`docs/03` §3). Lo elegido **no es una barrera**:
/// es el foco del agente, que queda escrito en su `AGENTS.md`. La pantalla lo dice con claridad.
struct SourcesStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        StepScaffold(step: .sources) {
            VStack(alignment: .leading, spacing: Space.s16) {
                Label("sources.intro", systemImage: "info.circle")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)

                if wizard.connectedTools.isEmpty {
                    Text("sources.none")
                        .font(.galenoBody)
                        .foregroundStyle(Color.ink700)
                } else {
                    ForEach(wizard.connectedTools, id: \.self) { tool in
                        SourceSection(tool: tool)
                    }
                }
            }
        }
        .tint(Color.moss700)
        .onAppear { wizard.beginSources() }
    }
}

extension Tool {
    /// Cómo se llaman, en plural, las cosas que se eligen de esta herramienta (para las claves
    /// `sources.loading.<slug>`, `.failed.<slug>`…).
    var sourceNounSlug: String {
        switch self {
        case .slack: "channels"
        case .whatsapp: "chats"
        case .notion: "pages"
        case .googleWorkspace, .googleMeet: "folders"
        case .gmail: "labels"
        case .jira: "projects"
        case .fireflies, .granola, .fathom: "meetings"
        }
    }
}

/// Una herramienta: su nombre, y debajo lo que se puede elegir (cargando, la lista, o un aviso).
private struct SourceSection: View {
    @EnvironmentObject private var wizard: WizardState
    let tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack(spacing: Space.s8) {
                ToolIcon(tool: tool, size: 22, color: Color.ink900)
                Text(verbatim: tool.displayName(in: wizard.language))
                    .font(.galenoBody.weight(.semibold))
                    .foregroundStyle(Color.ink900)
                Spacer()
                countLabel
            }
            content
        }
        .padding(Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.parchment100, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.parchment300, lineWidth: 1))
    }

    private var flow: SourcesFlow? { wizard.sourcesFlow }

    @ViewBuilder
    private var countLabel: some View {
        let selection = wizard.sourceSelection(for: tool)
        if !selection.readsEverything, !selection.selected.isEmpty {
            Text(selection.selected.count == 1 ? "sources.selected.one" : "sources.selected.other \(selection.selected.count)")
                .font(.galenoCaption)
                .foregroundStyle(Color.moss700)
        }
    }

    @ViewBuilder
    private var content: some View {
        if tool.selectableSourceKinds.isEmpty {
            // Reuniones transcritas: no hay nada que elegir, lee todo.
            Text("sources.everything.transcripts")
                .font(.galenoCaption)
                .foregroundStyle(Color.ink700)
        } else {
            switch flow?.load(of: tool) {
            case .loading, nil:
                HStack(spacing: Space.s8) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey("sources.loading." + tool.sourceNounSlug))
                            .font(.galenoCaption)
                            .foregroundStyle(Color.ink900)
                        if tool != .whatsapp {
                            Text("sources.loading.hint")
                                .font(.galenoCaption)
                                .foregroundStyle(Color.ink500)
                        }
                    }
                }
            case .failed:
                failed
            case .loaded(let list, let isPartial):
                if list.isEmpty {
                    Text(LocalizedStringKey("sources.empty." + tool.sourceNounSlug))
                        .font(.galenoCaption)
                        .foregroundStyle(Color.ink700)
                } else {
                    SourceList(tool: tool, sources: list, isPartial: isPartial)
                }
            }
        }
    }

    /// No se pudo listar: nunca bloquea. Se reintenta o se deja que el agente lo lea todo.
    @ViewBuilder
    private var failed: some View {
        let readsEverything = wizard.sourceSelection(for: tool).readsEverything
        VStack(alignment: .leading, spacing: Space.s8) {
            Text(LocalizedStringKey("sources.failed." + tool.sourceNounSlug))
                .font(.galenoCaption)
                .foregroundStyle(Color.seal700)
            HStack(spacing: Space.s12) {
                Button("sources.retry") { flow?.retry(tool) }
                    .buttonStyle(.bordered)
                Toggle("sources.readAll", isOn: Binding(
                    get: { readsEverything },
                    set: { wizard.setReadsEverything($0, for: tool) }))
                    .toggleStyle(.checkbox)
                    .font(.galenoCaption)
            }
            .controlSize(.small)
            if readsEverything {
                Text("sources.readAll.note")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
            }
        }
    }
}

/// La lista con casillas. Con muchas (WhatsApp puede tener cientos de chats) lleva un buscador y
/// su propio desplazamiento, para no empujar el resto de la pantalla.
private struct SourceList: View {
    @EnvironmentObject private var wizard: WizardState
    let tool: Tool
    let sources: [Source]
    let isPartial: Bool

    @State private var query = ""

    private var shown: [Source] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return sources }
        return sources.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            if sources.count > 8 {
                TextField(
                    LocalizedStringKey("sources.search." + tool.sourceNounSlug), text: $query
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(shown) { source in
                        Toggle(isOn: Binding(
                            get: { wizard.isSourceSelected(source, in: tool) },
                            set: { _ in wizard.toggleSource(source, in: tool) })
                        ) {
                            HStack(spacing: Space.s8) {
                                Text(verbatim: source.name)
                                    .font(.galenoBody)
                                    .foregroundStyle(Color.ink900)
                                    .lineLimit(1)
                                if let key = kindKey(source.kind) {
                                    Text(LocalizedStringKey(key))
                                        .font(.galenoCaption)
                                        .foregroundStyle(Color.ink500)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    if shown.isEmpty {
                        Text("sources.noMatch")
                            .font(.galenoCaption)
                            .foregroundStyle(Color.ink500)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 170)

            let selection = wizard.sourceSelection(for: tool)
            if selection.selected.isEmpty && !selection.readsEverything {
                Text("sources.noneSelected")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
            }
            if isPartial {
                Text("sources.partial")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
            }
        }
    }

    /// Solo se rotula lo que distingue: grupo/chat en WhatsApp y página/base de datos en Notion.
    private func kindKey(_ kind: SourceKind) -> String? {
        switch kind {
        case .group: "sources.kind.group"
        case .chat: "sources.kind.chat"
        case .database: "sources.kind.database"
        case .page: tool == .notion ? "sources.kind.page" : nil
        case .channel, .folder, .project, .mailLabel: nil
        }
    }
}

#Preview {
    let state = WizardState()
    state.toggle(.slack)
    state.toggle(.fireflies)
    return SourcesStepView()
        .environmentObject(state)
        .frame(width: WindowMetrics.width, height: 520)
        .background(Color.parchment50)
}
