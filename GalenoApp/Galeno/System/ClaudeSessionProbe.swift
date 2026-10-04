import Foundation

/// Cómo ve **una sesión real** de Claude Code cada servidor MCP.
///
/// Hace falta para los conectores de la cuenta de Claude (Gmail, Google Drive…): `claude mcp get` y
/// `claude mcp list` los dan por «Connected» aunque les falte la autorización de Google (comprobado: el
/// conector respondía «requires authentication» al usarlo mientras `get` decía «Connected»). El estado
/// de verdad lo dice el primer evento de una sesión (`system` / `init`, campo `mcp_servers`).
nonisolated protocol SessionProbing: Sendable {
    /// Nombre del servidor → estado tal cual lo da Claude Code (`connected`, `needs-auth`, `failed`,
    /// `pending`). `nil` si no se pudo leer.
    func serverStatuses(claudePath: String) async -> [String: String]?
}

/// Arranca `claude -p` con salida en eventos, lee el evento inicial y **corta el proceso ahí**: no espera
/// la respuesta del modelo, así que la consulta no gasta la cuota del usuario más que el arranque.
nonisolated struct ClaudeSessionProbe: SessionProbing {
    var timeout: TimeInterval = 45

    func serverStatuses(claudePath: String) async -> [String: String]? {
        let timeout = self.timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.probe(claudePath: claudePath, timeout: timeout))
            }
        }
    }

    private static func probe(claudePath: String, timeout: TimeInterval) -> [String: String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = [
            "-p", "ok", "--model", "haiku", "--output-format", "stream-json", "--verbose",
            "--max-turns", "1", "--no-session-persistence",
        ]
        // Un directorio neutro: sin `CLAUDE.md` ni ajustes de proyecto de por medio.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer {
            watchdog.cancel()
            if process.isRunning { process.terminate() }
        }

        var buffer = Data()
        let reader = pipe.fileHandleForReading
        while true {
            let chunk = reader.availableData  // espera hasta que haya datos o se cierre la salida
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                if let statuses = parseInit(line) { return statuses }
            }
        }
    }

    /// `{"type":"system","subtype":"init","mcp_servers":[{"name":"claude.ai Google Drive","status":"needs-auth"}…]}`
    /// → `["claude.ai Google Drive": "needs-auth"]`. `nil` si la línea no es ese evento.
    static func parseInit(_ line: Data) -> [String: String]? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["type"] as? String == "system", object["subtype"] as? String == "init",
            let servers = object["mcp_servers"] as? [[String: Any]]
        else { return nil }
        var statuses: [String: String] = [:]
        for server in servers {
            if let name = server["name"] as? String, let status = server["status"] as? String {
                statuses[name] = status
            }
        }
        return statuses
    }
}
