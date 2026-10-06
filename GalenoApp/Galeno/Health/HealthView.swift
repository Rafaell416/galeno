import GalenoCore
import SwiftUI

/// La vista de salud (`docs/03` §3b, B1): conexiones, WhatsApp, skills y carpetas, en secciones a filetes, como el
/// resto del libro de registro. Sin láminas ni tarjetas.
struct HealthView: View {
    @ObservedObject var model: HealthModel
    @ObservedObject var home: HomeModel
    let onBack: () -> Void
    @Environment(\.locale) private var locale

    private var language: Language { Language(rawValue: locale.identifier) ?? .spanish }
    /// Cerrando la sesión o dejando `sync` listo: salir a medias dejaría WhatsApp a medio vincular.
    private var isBusyRelinking: Bool { model.relink == .closing || model.relink == .finishing }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    connectionsSection
                    if model.usesWhatsApp { whatsappSection }
                    skillsSection
                    foldersSection
                }
                .padding(.horizontal, Space.s48)
                .padding(.top, 22)
                .padding(.bottom, Space.s16)
            }
            .scrollBounceBehavior(.basedOnSize)
            Rectangle().fill(Color.parchment300).frame(height: 1)
            HStack {
                Button("health.back", action: back)
                    .buttonStyle(InkButtonStyle(.secondary, padding: 22))
                    .disabled(isBusyRelinking)
                Spacer(minLength: 0)
                Button("health.refresh") { model.refresh() }
                    .buttonStyle(InkButtonStyle(.primary, padding: 26, isLoading: model.isChecking))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isChecking || model.reconnecting != nil || model.relink != .idle)
            }
            .padding(.horizontal, Space.s48)
            .padding(.vertical, 14)
        }
        .background(Color.parchment50)
        .overlay { GrainOverlay() }
        .overlay {
            if model.relink != .idle {
                RelinkPanelView(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: Motion.micro), value: model.relink)
        .onExitCommand {
            if model.relink != .idle { model.cancelRelink() } else { back() }
        }
        .onAppear { model.refresh() }
        .onDisappear { model.stop() }
    }

    private func back() {
        guard !isBusyRelinking else { return }
        model.stop()
        onBack()
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            PortraitMark(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                StepTitle(text: Text("health.title"), size: 28)
                Text("health.subtitle").font(Typo.list).foregroundStyle(Color.ink700)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Conexiones

    private var connectionsSection: some View {
        HealthSection("health.connections") {
            if !model.claudeAvailable {
                Text("health.noClaude").font(Typo.text(14)).foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.connections.isEmpty {
                Text(LocalizedStringKey(model.isChecking ? "health.checking" : "health.connections.none"))
                    .font(Typo.text(14)).foregroundStyle(Color.ink500)
            } else {
                ForEach(model.connections) { row in
                    ConnectionLine(model: model, row: row, language: language)
                }
            }
        }
    }

    // MARK: WhatsApp

    private var whatsappSection: some View {
        HealthSection("health.whatsapp", trailing: bridgeVersionText) {
            if let health = model.whatsapp {
                whatsappLines(health)
            } else {
                HStack(spacing: 8) {
                    InkSpinner(size: 12)
                    Text("health.checking").font(Typo.text(14)).foregroundStyle(Color.ink500)
                }
            }
        }
    }

    @ViewBuilder
    private func whatsappLines(_ health: HealthModel.WhatsAppHealth) -> some View {
        if health.status == nil {
            Text("health.whatsapp.noBridge").font(Typo.text(14)).foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Fact("health.whatsapp.session", value: sessionText(health), tone: health.isLinked ? .good : .warn)
            Fact("health.whatsapp.sync", value: syncText(health.sync), tone: health.sync == .running ? .good : .warn)
            if let days = health.daysLinked() {
                Fact("health.whatsapp.linked", value: daysText(days), tone: .neutral)
            }
            if health.shouldRelink(), let days = health.daysLinked() {
                NoticePanel(kind: .ochre) {
                    Text(verbatim: Localized.string("health.whatsapp.rotate %lld %lld", days, WhatsAppSession.estimatedRotationDays, locale: locale))
                        .font(Typo.text(14)).foregroundStyle(Color.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if health.isLinked, health.sync != .running {
                Text("health.whatsapp.syncHint").font(Typo.text(13)).foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(LocalizedStringKey(health.isLinked ? "health.whatsapp.relink" : "health.whatsapp.link")) { model.askRelink() }
                    .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 16))
                    .disabled(model.relink != .idle)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    /// «Puente 0.3.0», a la derecha del rótulo. Sin respuesta del puente no hay versión que mostrar.
    private var bridgeVersionText: String? {
        model.whatsapp?.status.map { Localized.string("health.whatsapp.version %@", $0.bridgeVersion, locale: locale) }
    }

    private func sessionText(_ health: HealthModel.WhatsAppHealth) -> String {
        guard health.isLinked else { return Localized.string("health.whatsapp.notLinked", locale: locale) }
        if let number = health.status?.number, !number.isEmpty {
            return Localized.string("health.whatsapp.linkedAs %@", "+" + number, locale: locale)
        }
        return Localized.string("health.whatsapp.linkedPlain", locale: locale)
    }

    private func syncText(_ state: WhatsAppSyncState) -> String {
        switch state {
        case .running: Localized.string("health.whatsapp.sync.running", locale: locale)
        case .stopped: Localized.string("health.whatsapp.sync.stopped", locale: locale)
        case .notInstalled: Localized.string("health.whatsapp.sync.notInstalled", locale: locale)
        }
    }

    private func daysText(_ days: Int) -> String {
        switch days {
        case 0: Localized.string("health.whatsapp.days.today", locale: locale)
        case 1: Localized.string("health.whatsapp.days.one", locale: locale)
        default: Localized.string("health.whatsapp.days.other %lld", days, locale: locale)
        }
    }

    // MARK: Skills

    private var skillsSection: some View {
        HealthSection("health.skills") {
            Text(LocalizedStringKey(model.canUpdateSkills ? "health.skills.body" : "health.skills.soon"))
                .font(Typo.text(14)).foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("health.skills.update") { model.updateSkills() }
                    .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 16, isLoading: model.isUpdatingSkills))
                    .disabled(!model.canUpdateSkills || model.isUpdatingSkills)
                if model.skillsUpdateFailed {
                    Text("health.skills.failed").font(Typo.text(13)).foregroundStyle(Color.ochre700)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Carpetas

    private var missingFolders: [HomeAgent] { home.agents.filter { !$0.folderExists } }

    private var foldersSection: some View {
        HealthSection("health.folders") {
            if missingFolders.isEmpty {
                Fact("health.folders.ok", value: nil, tone: .good)
            } else {
                ForEach(missingFolders) { agent in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: agent.name).font(Typo.text(15.5, .semibold)).foregroundStyle(Color.ink900)
                            Text("home.folderMissing").font(Typo.text(13)).foregroundStyle(Color.ink500)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        // Los diálogos viven en el inicio: se pide ahí y se vuelve a verlo.
                        HStack(spacing: 16) {
                            Button("home.folder.regenerate") {
                                home.askRegenerate(agent)
                                back()
                            }
                            Button("home.folder.remove") {
                                home.askDelete(agent)
                                back()
                            }
                        }
                        .buttonStyle(LinkTextStyle())
                    }
                }
            }
        }
    }
}

// MARK: - Piezas

/// Una sección: rótulo en versalitas y un filete encima, como en la Revisión.
private struct HealthSection<Content: View>: View {
    let title: String
    let trailing: String?
    @ViewBuilder var content: Content

    init(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(Color.parchment300).frame(height: 1)
            HStack(alignment: .firstTextBaseline) {
                SmallCapsLabel(title, size: 12).foregroundStyle(Color.ink500)
                Spacer(minLength: 8)
                if let trailing {
                    Text(verbatim: trailing).font(Typo.text(12)).foregroundStyle(Color.ink500)
                }
            }
            .padding(.top, 2)
            content
        }
    }
}

/// «Servicio de fondo — Corriendo»: una etiqueta y su valor, con un punto que no depende solo del color.
private struct Fact: View {
    enum Tone { case good, warn, neutral }

    let key: String
    let value: String?
    let tone: Tone
    @Environment(\.locale) private var locale

    init(_ key: String, value: String?, tone: Tone) {
        self.key = key
        self.value = value
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            marker
            Text(verbatim: Localized.string(key, locale: locale))
                .font(Typo.text(15)).foregroundStyle(tone == .neutral || value == nil ? Color.ink900 : Color.ink700)
            Spacer(minLength: 8)
            if let value {
                Text(verbatim: value).font(Typo.text(15, .semibold)).foregroundStyle(color)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var color: Color {
        switch tone {
        case .good: .moss700
        case .warn: .ochre700
        case .neutral: .ink900
        }
    }

    /// ✓ / ! / · : la forma dice lo mismo que el color.
    private var marker: some View {
        Text(verbatim: tone == .good ? "✓" : tone == .warn ? "!" : "·")
            .font(Typo.text(13, .bold)).foregroundStyle(color)
            .frame(width: 12)
            .accessibilityHidden(true)
    }
}

/// Un renglón de conexión: logo, nombre, estado y, si hace falta, «Reconectar».
private struct ConnectionLine: View {
    @ObservedObject var model: HealthModel
    let row: HealthModel.ConnectionRow
    let language: Language
    @Environment(\.locale) private var locale

    private var isReconnecting: Bool { model.reconnecting == row.tool }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                ToolIcon(tool: row.tool, size: 18, color: .ink700)
                    .accessibilityHidden(true)
                Text(verbatim: row.tool.displayName(in: language))
                    .font(Typo.text(15.5)).foregroundStyle(Color.ink900)
                Spacer(minLength: 8)
                if row.state == .checking {
                    InkSpinner(size: 12)
                }
                Text(verbatim: stateText).font(Typo.text(14, .semibold)).foregroundStyle(stateColor)
                if row.state.canReconnect {
                    Button("health.reconnect") { model.reconnect(row.tool) }
                        .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 14, isLoading: isReconnecting))
                        .disabled(model.reconnecting != nil)
                }
            }
            if let issue = model.reconnectIssues[row.tool] {
                Text(verbatim: Localized.string(issueKey(issue), locale: locale))
                    .font(Typo.text(13)).foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 30)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var stateText: String {
        let key: String =
            switch row.state {
            case .checking: "health.state.checking"
            case .connected: "health.state.connected"
            case .pending: "health.state.pending"
            case .needsAuthorization: "health.state.needsAuthorization"
            case .failed: "health.state.failed"
            case .missing: "health.state.missing"
            case .unknown: "health.state.unknown"
            }
        return Localized.string(key, locale: locale)
    }

    private var stateColor: Color {
        switch row.state {
        case .connected: .moss700
        case .needsAuthorization, .failed, .missing: .ochre700
        case .checking, .pending, .unknown: .ink500
        }
    }

    private func issueKey(_ issue: HealthModel.ReconnectIssue) -> String { issue.messageKey }
}

// MARK: - Re-vincular WhatsApp

/// El re-vincular: la advertencia de siempre (el mismo texto, sin tocarlo), después el QR en pantalla. Va sobre
/// el fondo atenuado, como los diálogos del inicio.
struct RelinkPanelView: View {
    @ObservedObject var model: HealthModel
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            Color.ink900.opacity(0.30)
                .contentShape(Rectangle())
                .onTapGesture { if canCancel { model.cancelRelink() } }
            VStack(alignment: .leading, spacing: 14) {
                content
                buttons
            }
            .padding(24)
            .frame(width: panelWidth, alignment: .leading)
            .background(Color.parchment50)
            .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
        }
        .onChange(of: model.relink) { _, phase in
            if phase == .done { Sounds.play(.connected) }
            if case .failed = phase { Sounds.play(.failed) }
        }
    }

    private var canCancel: Bool { model.relink != .closing && model.relink != .finishing }

    private var panelWidth: CGFloat {
        if case .qr = model.relink { return 640 }
        return 520
    }

    @ViewBuilder
    private var content: some View {
        switch model.relink {
        case .idle:
            EmptyView()
        case .confirming:
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(model.whatsapp?.isLinked == true ? "health.relink.title" : "health.link.title"))
                    .font(Typo.display(26)).foregroundStyle(Color.ink900)
                if model.whatsapp?.isLinked == true {
                    Text("health.relink.body").font(Typo.text(14.5)).foregroundStyle(Color.ink700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                WhatsAppWarning()
            }
        case .closing:
            working("health.relink.closing")
        case .qr(let image):
            QRPanel(image: image)
        case .finishing:
            working("health.relink.finishing")
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 8) {
                Text("health.relink.failed.title").font(Typo.display(26)).foregroundStyle(Color.ink900)
                Text(verbatim: Localized.string(failureKey(failure), locale: locale))
                    .font(Typo.text(14.5)).foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .done:
            VStack(alignment: .leading, spacing: 8) {
                Text("health.relink.done.title").font(Typo.display(26)).foregroundStyle(Color.ink900)
                Text("health.relink.done.body").font(Typo.text(14.5)).foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func working(_ key: String) -> some View {
        HStack(spacing: 10) {
            InkSpinner(size: 16)
            Text(LocalizedStringKey(key)).font(Typo.text(15)).foregroundStyle(Color.ink900)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
    }

    private func failureKey(_ failure: HealthModel.RelinkFailure) -> String {
        switch failure {
        case .bridgeMissing: "health.relink.failed.bridgeMissing"
        case .couldNotClose: "health.relink.failed.couldNotClose"
        case .qrExpired: "health.relink.failed.qrExpired"
        case .failed: "health.relink.failed.generic"
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            switch model.relink {
            case .confirming:
                Button("wizard.cancel") { model.cancelRelink() }
                    .buttonStyle(InkButtonStyle(.secondary, padding: 20))
                Button("health.relink.confirm") { model.confirmRelink() }
                    .buttonStyle(InkButtonStyle(.primary, padding: 22))
                    .keyboardShortcut(.defaultAction)
            case .qr:
                Button("wizard.cancel") { model.cancelRelink() }
                    .buttonStyle(InkButtonStyle(.secondary, padding: 20))
            case .failed:
                Button("health.relink.close") { model.dismissRelink() }
                    .buttonStyle(InkButtonStyle(.secondary, padding: 20))
                Button("health.relink.retry") { model.askRelink() }
                    .buttonStyle(InkButtonStyle(.primary, padding: 22))
            case .done:
                Button("health.relink.close") { model.dismissRelink() }
                    .buttonStyle(InkButtonStyle(.primary, padding: 22))
                    .keyboardShortcut(.defaultAction)
            case .idle, .closing, .finishing:
                EmptyView()
            }
        }
        .padding(.top, 4)
    }
}
