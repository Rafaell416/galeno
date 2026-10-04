import Darwin
import Foundation

/// Un secreto OAuth (`client_secret`) en memoria, de paso.
///
/// Está hecho para que **no se pueda dejar escapar por descuido** (`AGENTS.md`: nunca a
/// disco, nunca a un log, nunca a una propiedad que sobreviva a la llamada):
/// - no es `Codable`, `Hashable` ni `Equatable`: no se puede guardar, ni usar de clave, ni
///   comparar por accidente;
/// - `description`, `debugDescription` y el espejo (`dump`, `Mirror`) lo ocultan, así que un
///   `print`, un log o el mensaje de una prueba que falla no lo muestran;
/// - sus bytes se borran al terminar (`wipe()`) y al liberarse.
///
/// Lo único que lo expone es `withValue`, y quien lo usa solo debe pasarlo al entorno de un
/// proceso (`MCP_CLIENT_SECRET`), nunca a los argumentos.
///
/// Límite honesto: una `String` de Swift no se puede borrar de la memoria. Los bytes de
/// este objeto sí; las copias temporales que crea `withValue` o el campo de texto donde el
/// usuario pegó el valor, no. Se reduce el tiempo de vida, no se elimina.
nonisolated final class OAuthSecret: @unchecked Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    private let lock = NSLock()
    private var bytes: [UInt8]

    init(_ value: String) {
        bytes = Array(value.utf8)
    }

    deinit { wipe() }

    var isEmpty: Bool { lock.withLock { bytes.isEmpty } }

    /// Da el valor durante `body`. No lo guardes.
    func withValue<R>(_ body: (String) throws -> R) rethrows -> R {
        let value = lock.withLock { String(decoding: bytes, as: UTF8.self) }
        return try body(value)
    }

    /// Igual que `withValue`, para quien tiene que esperar algo (una petición) mientras lo usa.
    func withValueAsync<R>(_ body: (String) async throws -> R) async rethrows -> R {
        let value = lock.withLock { String(decoding: bytes, as: UTF8.self) }
        return try await body(value)
    }

    /// Borra los bytes. Después `isEmpty` es `true`.
    func wipe() {
        lock.withLock {
            bytes.withUnsafeMutableBytes { buffer in
                if let base = buffer.baseAddress { _ = memset_s(base, buffer.count, 0, buffer.count) }
            }
            bytes.removeAll()
        }
    }

    var description: String { "OAuthSecret(oculto)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:], displayStyle: .class) }
}

/// Con qué app OAuth propia se registra un servidor MCP: la que creó el cliente
/// (Slack, Google). Lleva el secreto, así que **no se debe copiar ni guardar**.
nonisolated struct OAuthClientRegistration: Sendable {
    var clientID: String
    /// El puerto del callback local (Slack: `SlackOAuth.callbackPort`). Tiene que coincidir
    /// con la URL de redirección registrada en la app.
    var callbackPort: Int?
    var secret: OAuthSecret?
    /// El identificador de la app (`A0123ABCD`), público. Solo sirve para llevar al usuario a la
    /// página de su app; no es parte del registro en Claude Code.
    var appID: String?

    /// Un `client_id` es un identificador público, pero se pasa como argumento: se rechaza
    /// lo que pudiera leerse como una opción (`--algo`) o traiga espacios y comillas.
    static func isValidClientID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{2,200}$"#, options: .regularExpression) != nil
    }
}
