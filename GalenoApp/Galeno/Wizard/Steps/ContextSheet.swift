import AppKit
import GalenoCore
import SwiftUI
import UniformTypeIdentifiers

/// «Trae lo que ya sabes de tu proyecto» (paso 3): para quien ya habló del proyecto en claude.ai.
/// Dos caminos que se pueden combinar: copiar un mensaje para su chat de Claude y pegar aquí la
/// respuesta, o elegir/soltar archivos. Todo queda como texto en la carpeta del agente
/// (`memoria/contexto/`); el agente lo lee en su primera sesión como dato, no como orden.
struct ContextSheet: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var pasted = ""
    @State private var copiedPrompt = false
    @State private var issue: LocalizedStringKey?
    @State private var dropTargeted = false

    private var agentName: String {
        let name = wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Localized.string("context.yourAgent", locale: locale) : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(text: Text("context.title"), size: 26)
                .padding(.bottom, 8)
            Text("context.intro \(agentName)")
                .font(Typo.list)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)

            NumberedLine(number: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s12) {
                    Text("context.step1").font(Typo.list).foregroundStyle(Color.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { copyPrompt() } label: {
                        CopyLabel(copied: copiedPrompt, idle: "context.copyPrompt", done: "detection.copied")
                    }
                    .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 14))
                }
            }
            .padding(.bottom, 12)

            NumberedLine(number: 2) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("context.step2").font(Typo.list).foregroundStyle(Color.ink900)
                    pasteArea
                    HStack(spacing: Space.s12) {
                        Button("context.add") { addPasted() }
                            .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 14))
                            .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("context.pickFiles") { pickFiles() }
                            .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 14))
                        Spacer(minLength: 0)
                    }
                    Text("context.dropHint")
                        .font(Typo.text(13))
                        .foregroundStyle(Color.ink500)
                }
            }

            if let issue {
                Text(issue)
                    .font(Typo.text(13))
                    .foregroundStyle(Color.seal700)
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            if !wizard.contextItems.isEmpty { items.padding(.top, 14) }

            Spacer(minLength: 12)
            HStack(alignment: .firstTextBaseline) {
                Text("context.privacy \(agentName)")
                    .font(Typo.text(12.5))
                    .foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s16)
                Button("context.done") {
                    addPasted()
                    dismiss()
                }
                .buttonStyle(.inkPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 600)
        .background(Color.parchment50)
        .overlay(dropTargeted ? Rectangle().strokeBorder(Color.ink900, lineWidth: 1.5).padding(8) : nil)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in addFile(url) }
                }
            }
            return true
        }
        .animation(.easeOut(duration: Motion.micro), value: issue == nil)
    }

    // MARK: Piezas

    private var pasteArea: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $pasted)
                .font(Typo.text(14))
                .scrollContentBackground(.hidden)
                .padding(6)
            if pasted.isEmpty {
                Text("context.paste.placeholder")
                    .font(Typo.text(14))
                    .foregroundStyle(Color.ink500)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 96)
        .background(Color.parchment100)
        .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
    }

    private var items: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(wizard.contextItems) { item in
                    HStack(spacing: Space.s12) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Color.ink500)
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
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: Motion.micro), value: wizard.contextItems.count)
        }
        .frame(maxHeight: 120)
    }

    // MARK: Acciones

    private func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Localized.string("context.prompt", locale: locale), forType: .string)
        copiedPrompt = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedPrompt = false
        }
    }

    private func addPasted() {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let title = Localized.string("context.pasted.title", locale: locale)
        if let problem = wizard.addContext(ContextFile(title: title, text: text)) {
            issue = Self.message(for: problem)
        } else {
            pasted = ""
            issue = nil
        }
    }

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
