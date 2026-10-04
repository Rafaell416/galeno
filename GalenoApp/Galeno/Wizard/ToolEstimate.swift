import GalenoCore

/// Cuánto tarda conectar cada herramienta, para el "~X min" del paso 4.
///
/// **Son estimaciones nuestras**: la especificación solo da un ejemplo
/// ("5 herramientas · ~8 min"). Se calibran con la prueba de la Fase 4 (conectar
/// 5 herramientas en menos de 12 minutos) y se cambian aquí, en un solo sitio.
extension Tool {
    var estimatedSetupMinutes: Int {
        switch self {
        // QR más la sincronización inicial del bridge.
        case .whatsapp: 3
        // Traen su propia app OAuth: la creamos con el cliente y luego conecta.
        case .slack, .gmail, .googleWorkspace: 2
        // OAuth hospedado, sin nada previo.
        case .notion, .jira, .fireflies, .granola, .fathom, .claudeDesign: 1
        // Se lee con Drive: no hay nada que conectar aparte.
        case .googleMeet: 0
        }
    }
}

enum ToolEstimate {
    /// La suma de las herramientas elegidas, de 1 minuto como mínimo.
    static func minutes(for tools: [Tool]) -> Int {
        max(1, tools.reduce(0) { $0 + $1.estimatedSetupMinutes })
    }
}
