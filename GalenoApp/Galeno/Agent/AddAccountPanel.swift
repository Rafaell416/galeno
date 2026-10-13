import GalenoCore
import SwiftUI

/// En qué va «Añadir otra cuenta», en el detalle del agente y en el asistente.
enum AddAccountPhase: Equatable {
    case idle
    /// Registrando y esperando a que el usuario autorice en su navegador.
    case working
    case failed(AccountConnector.Issue)
}

/// «Añadir otra cuenta»: el nombre con el que el usuario la reconoce («Trabajo»), y la conexión. Se abre el navegador para
/// autorizar; ahí elige la cuenta o el espacio de trabajo que quiere añadir (si ya tenía una sesión abierta, es la que verá
/// primero). La cuenta entra al agente con sus propias reglas de permiso: cada una lleva las suyas.
///
/// La misma hoja para el detalle del agente y para la revisión del asistente: quien la pone decide qué pasa al conectar.
struct AddAccountPanel: View {
    let toolName: String
    @Binding var draft: String
    let phase: AddAccountPhase
    var error: String?
    let onConnect: () -> Void
    let onCancel: () -> Void
    @Environment(\.locale) private var locale

    private var isWorking: Bool { phase == .working }
    private var issue: AccountConnector.Issue? {
        if case .failed(let issue) = phase { return issue }
        return nil
    }
    private var canConnect: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
    }

    var body: some View {
        ZStack {
            Color.ink900.opacity(0.30)
                .contentShape(Rectangle())
                .onTapGesture { if !isWorking { onCancel() } }
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: Localized.string("agent.account.add.title %@", toolName, locale: locale))
                    .font(Typo.display(26)).foregroundStyle(Color.ink900)
                Text("agent.account.add.sub")
                    .font(Typo.text(14.5)).foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                RuleTextField(
                    "agent.account.add.field", text: $draft, prompt: "agent.account.add.placeholder",
                    font: Typo.display(24), autofocus: true, isError: issue.map(isNameIssue) ?? false
                )
                .onChange(of: draft) { _, value in
                    if value.count > AccountConnector.maxNameLength {
                        draft = String(value.prefix(AccountConnector.maxNameLength))
                    }
                }
                .onSubmit { if canConnect { onConnect() } }
                .disabled(isWorking)

                Text(
                    verbatim: isWorking
                        ? Localized.string("agent.account.add.working", locale: locale)
                        : Localized.string("agent.account.add.browser", locale: locale)
                )
                .font(Typo.text(13.5)).foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
                if let issue {
                    Text(verbatim: Localized.string(Self.key(for: issue), locale: locale))
                        .font(Typo.text(13.5)).foregroundStyle(Color.seal700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(verbatim: error).font(Typo.text(13.5)).foregroundStyle(Color.seal700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("wizard.cancel", action: onCancel)
                        .buttonStyle(InkLinkStyle(size: 15))
                    Spacer(minLength: 0)
                    Button("agent.account.add.connect", action: onConnect)
                        .buttonStyle(InkButtonStyle(.primary, padding: 22, isLoading: isWorking))
                        .disabled(!canConnect)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(width: 520, alignment: .leading)
            .background(Color.parchment50)
            .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
        }
        .onExitCommand(perform: onCancel)
    }

    private func isNameIssue(_ issue: AccountConnector.Issue) -> Bool {
        switch issue {
        case .invalidName, .alreadyExists, .nameInUse: true
        default: false
        }
    }

    /// Un error dice su causa real, en tres partes y sin exclamaciones.
    static func key(for issue: AccountConnector.Issue) -> String {
        switch issue {
        case .invalidName: "agent.account.issue.invalidName"
        case .alreadyExists: "agent.account.issue.alreadyExists"
        case .unsupported: "agent.account.issue.unsupported"
        case .nameInUse: "agent.account.issue.nameInUse"
        case .couldNotRegister: "agent.account.issue.couldNotRegister"
        case .notAuthorizedInTime: "agent.account.issue.notAuthorizedInTime"
        case .loginFailed: "agent.account.issue.loginFailed"
        case .stillNotConnected: "agent.account.issue.stillNotConnected"
        case .claudeOutdated: "agent.account.issue.claudeOutdated"
        }
    }
}
