/// Las herramientas que el agente puede conectar en v0.0.1, tal como aparecen
/// en la grilla del paso 4 del wizard.
public enum Tool: String, Codable, CaseIterable, Sendable, Identifiable {
    case whatsapp
    case slack
    case notion
    case googleWorkspace = "google-workspace"
    case gmail
    case jira
    case fireflies
    case granola
    case fathom
    case googleMeet = "google-meet"

    public var id: String { rawValue }
}

/// Cómo se conecta una herramienta en el sub-wizard del paso 5.
public enum ConnectionMethod: String, Codable, CaseIterable, Sendable {
    /// OAuth oficial del proveedor.
    case oauth
    /// Código QR. Solo WhatsApp, que se vincula como dispositivo usando el
    /// protocolo de WhatsApp Web, de forma no oficial y con advertencia
    /// explícita en pantalla.
    case qrCode = "qr-code"
}

extension Tool {
    /// El nombre que el usuario ve.
    public var displayName: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .slack: "Slack"
        case .notion: "Notion"
        case .googleWorkspace: "Google Drive, Docs y Sheets"
        case .gmail: "Gmail"
        case .jira: "Jira"
        case .fireflies: "Fireflies"
        case .granola: "Granola"
        case .fathom: "Fathom"
        case .googleMeet: "Google Meet"
        }
    }

    public var connectionMethod: ConnectionMethod {
        switch self {
        case .whatsapp: .qrCode
        case .slack, .notion, .googleWorkspace, .gmail, .jira,
            .fireflies, .granola, .fathom, .googleMeet:
            .oauth
        }
    }

    /// Si el agente puede escribir o enviar algo por esta herramienta.
    ///
    /// WhatsApp es `false` por línea roja: su MCP no tiene herramientas de
    /// envío, así que no es una capacidad que se pueda activar. Las de
    /// transcripción son `false` porque sus MCP oficiales son de solo lectura.
    public var allowsWriting: Bool {
        switch self {
        case .slack, .notion, .googleWorkspace, .gmail, .jira: true
        case .whatsapp, .fireflies, .granola, .fathom, .googleMeet: false
        }
    }

    /// Los tipos de fuente que el usuario puede elegir en el paso 6.
    ///
    /// Vacío significa que la herramienta no tiene fuentes que elegir: el
    /// agente ve todo lo que expone. Es el caso de las tres de transcripción.
    public var selectableSourceKinds: [SourceKind] {
        switch self {
        case .whatsapp: [.group, .chat]
        case .slack: [.channel]
        case .notion: [.page, .database]
        case .googleWorkspace: [.folder]
        case .gmail: [.mailLabel]
        case .jira: [.project]
        case .googleMeet: [.folder]
        case .fireflies, .granola, .fathom: []
        }
    }

    /// Las herramientas que deben estar conectadas para que esta funcione.
    ///
    /// Google Meet no tiene MCP propio: las transcripciones que genera Gemini
    /// caen en Drive, así que se leen con el MCP de Google Workspace.
    public var requires: [Tool] {
        switch self {
        case .googleMeet: [.googleWorkspace]
        case .whatsapp, .slack, .notion, .googleWorkspace, .gmail, .jira,
            .fireflies, .granola, .fathom:
            []
        }
    }
}
