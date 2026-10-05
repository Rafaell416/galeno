import AppKit
import GalenoCore
import SwiftUI
import UniformTypeIdentifiers

/// «Darle contexto» (rediseño «Activación»): después del nombre y antes de las herramientas. Opcional: una
/// línea sobre el proyecto y, si los hay, archivos que el agente leerá en su primera sesión. Se puede pasar
/// de largo sin tocar nada.
///
/// Los archivos quedan como texto en la carpeta del agente (`memoria/contexto/`), nunca en `AgentConfig` ni
/// en el borrador: son dato de terceros, y el agente los lee como dato, no como orden.
struct ContextStepView: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.locale) private var locale
    @Environment(\.galenoReduceMotion) private var reduceMotion

    @State private var issue: LocalizedStringKey?
    @State private var dropTargeted = false
    @State private var hoveringDrop = false
    @State private var showsClaudePath = false

    var body: some View {
        StepScaffold(step: .context, summarySize: 16, titleGap: 8, contentGap: 22) {
            VStack(alignment: .leading, spacing: 22) {
                projectField
                filesField
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
        .sheet(isPresented: $showsClaudePath) { ContextSheet() }
        .animation(.easeOut(duration: Motion.micro), value: issue == nil)
        .animation(.easeOut(duration: Motion.micro), value: wizard.contextItems.count)
    }

    // MARK: El proyecto

    private var counterColor: Color {
        let count = wizard.projectDescription.count
        if count >= WizardState.maxProjectDescriptionLength { return .seal700 }
        return count >= 120 ? .ochre700 : .ink500
    }

    private var projectField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                label("context.project.label")
                Spacer()
                // Desde 120 pasa a ocre; en el tope, a lacre, y el campo deja de aceptar.
                Text(verbatim: "\(wizard.projectDescription.count)/\(WizardState.maxProjectDescriptionLength)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(counterColor)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.1), value: wizard.projectDescription.count)
                    .opacity(wizard.projectDescription.isEmpty ? 0 : 1)
            }
            RuleTextField(
                "context.project.label", text: $wizard.projectDescription, prompt: "context.project.placeholder",
                font: Typo.text(17), autofocus: true, lines: 2
            )
            .onChange(of: wizard.projectDescription) { _, text in
                if text.count > WizardState.maxProjectDescriptionLength {
                    wizard.projectDescription = String(text.prefix(WizardState.maxProjectDescriptionLength))
                }
            }
        }
    }

    // MARK: Los archivos

    private var filesField: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("context.files.label")
            Button(action: pickFiles) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Color.ink700)
                        .offset(y: dropTargeted && !reduceMotion ? 2 : 0)
                    (Text("context.files.drop") + Text(verbatim: " ")
                        + Text("context.files.pick").underline().foregroundColor(Color.ink900))
                        .font(Typo.text(15))
                        .foregroundStyle(Color.ink700)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(dropTargeted || hoveringDrop ? Color.parchment100 : Color.clear)
                .overlay(
                    Rectangle().strokeBorder(
                        dropTargeted ? Color.ink900 : Color.parchment400,
                        style: StrokeStyle(lineWidth: dropTargeted ? 1.5 : 1, dash: dropTargeted ? [] : [4, 3]))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringDrop = $0 }
            .pointingHandOnHover()
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in addFile(url) }
                    }
                }
                return true
            }
            .animation(.easeOut(duration: Motion.micro), value: dropTargeted)
            .animation(.easeOut(duration: Motion.micro), value: hoveringDrop)

            if let issue {
                Text(issue)
                    .font(Typo.text(13))
                    .foregroundStyle(Color.seal700)
                    .padding(.top, 8)
                    .transition(.opacity)
            }

            if !wizard.contextItems.isEmpty { items.padding(.top, 10) }

            HStack(alignment: .firstTextBaseline, spacing: Space.s12) {
                Text("context.files.note")
                    .font(Typo.text(13))
                    .foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                // Para quien ya habló del proyecto en claude.ai: el camino de copiar y pegar, aparte.
                Button("context.fromClaude") { showsClaudePath = true }
                    .buttonStyle(InkLinkStyle(size: 13))
            }
            .padding(.top, 10)
        }
    }

    private var items: some View {
        VStack(spacing: 0) {
            ForEach(wizard.contextItems) { item in
                HStack(spacing: Space.s12) {
                    TracedShape(shape: CheckMark(), lineWidth: 1.5, color: .moss700, duration: 0.18)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                    Text(verbatim: item.file.title)
                        .font(Typo.text(14, .medium))
                        .foregroundStyle(Color.ink900)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("context.item.size \(item.file.text.count)")
                        .font(Typo.text(12.5))
                        .foregroundStyle(Color.ink500)
                    Spacer(minLength: 0)
                    Button("context.remove") { wizard.removeContext(item) }
                        .buttonStyle(InkButtonStyle(.tertiary, size: .bar, quiet: true))
                }
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
                .transition(.opacity)
            }
        }
    }

    private func label(_ key: String) -> some View {
        SmallCapsText(string: Localized.string(key, locale: locale), size: 13, tracking: 0.12)
            .foregroundStyle(Color.ink700)
            .padding(.bottom, 6)
    }

    // MARK: Acciones

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ContextImporter.allowedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(addFile)
    }

    private func addFile(_ url: URL) {
        do {
            let file = try ContextImporter.load(url)
            if let problem = wizard.addContext(file) { issue = Self.message(for: problem) } else { issue = nil }
        } catch ContextImporter.Failure.unsupported {
            issue = "context.error.unsupported"
        } catch ContextImporter.Failure.tooLarge {
            issue = "context.error.tooLarge"
        } catch {
            issue = "context.error.unreadable"
        }
    }

    private static func message(for issue: WizardState.ContextIssue) -> LocalizedStringKey {
        switch issue {
        case .tooMany: "context.error.tooMany"
        case .tooLong: "context.error.tooLong"
        case .empty: "context.error.empty"
        }
    }
}

#Preview {
    let state = WizardState()
    state.agentName = "Hera"
    return ContextStepView()
        .environmentObject(state)
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
