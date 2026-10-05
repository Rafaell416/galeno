/// El rol del agente, que el usuario elige en el primer paso del asistente.
///
/// Tres roles (decisión de Rafa, 5 oct 2026; antes solo producto): deciden cómo se presenta el agente en su
/// `AGENTS.md`, qué skills trae marcadas y en qué orden se le ofrecen las herramientas. Las reglas, los
/// permisos y los subagentes son los mismos para los tres. Los perfiles de dev, legal y salud siguen fuera.
public enum AgentRole: String, Codable, CaseIterable, Sendable {
    case productManager = "product-manager"
    case marketing
    case sales

    /// El nombre que el usuario ve.
    public var displayName: String { title(in: .english) }

    /// El nombre del rol en la pantalla: «Producto», «Marketing», «Comercial».
    public func title(in language: Language) -> String {
        switch (self, language) {
        case (.productManager, .spanish): "Producto"
        case (.productManager, .english): "Product"
        case (.marketing, _): "Marketing"
        case (.sales, .spanish): "Comercial"
        case (.sales, .english): "Sales"
        }
    }

    /// Los grupos de skills del catálogo que este rol trae marcados. «Seguimiento y reportes» y «Reuniones y
    /// descubrimiento» sirven a los tres.
    public var skillGroups: [String] {
        switch self {
        case .productManager: ["documents", "work", "reports", "meetings"]
        case .marketing: ["marketing", "reports", "meetings"]
        case .sales: ["sales", "reports", "meetings"]
        }
    }

    /// El orden en que se le ofrecen (y se conectan) las herramientas. Primero las que más usa ese oficio:
    /// producto empieza por Jira; marketing y comercial, por WhatsApp. Las que no están aquí van después,
    /// en el orden de `Tool.allCases`.
    public var toolOrder: [Tool] {
        switch self {
        case .productManager: [.jira, .notion, .slack, .googleWorkspace, .fathom, .whatsapp]
        case .marketing: [.whatsapp, .googleWorkspace, .slack, .notion, .fathom, .jira]
        case .sales: [.whatsapp, .gmail, .googleWorkspace, .slack, .notion, .fathom]
        }
    }

    /// Cuántas de las primeras vienen marcadas de fábrica en «Tus herramientas».
    public static let preselectedToolCount = 3

    /// Las herramientas que el paso «Tus herramientas» marca de fábrica para este rol.
    public var preselectedTools: [Tool] { Array(toolOrder.prefix(Self.preselectedToolCount)) }

    /// Todas las herramientas, en el orden de este rol.
    public func ordered(_ tools: [Tool]) -> [Tool] {
        let first = toolOrder.filter(tools.contains)
        return first + tools.filter { !first.contains($0) }
    }
}
