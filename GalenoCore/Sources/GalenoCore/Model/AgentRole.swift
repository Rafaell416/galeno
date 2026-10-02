/// El rol del agente, que el usuario elige en el paso 3 del wizard.
///
/// En v0.0.1 solo hay uno. Los perfiles de dev, legal y salud llegan en v0.3+,
/// cada uno con sus propios guardrails.
public enum AgentRole: String, Codable, CaseIterable, Sendable {
    case productManager = "product-manager"

    /// El nombre que el usuario ve.
    public var displayName: String {
        switch self {
        case .productManager: "Product Manager"
        }
    }
}
