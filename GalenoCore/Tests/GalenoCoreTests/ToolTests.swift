import XCTest

@testable import GalenoCore

final class ToolTests: XCTestCase {
    /// WhatsApp envía desde el 7 oct 2026 (`docs/09`), pero solo en la conexión de quien aceptó la advertencia
    /// que lo dice. Una conexión de antes (sin el dato) sigue solo leyendo.
    func testWhatsAppOnlyWritesOnceTheUserAcceptedSending() {
        XCTAssertTrue(Tool.whatsapp.allowsWriting)
        for accepted in [nil, false] as [Bool?] {
            let connection = ToolConnection(tool: .whatsapp, status: .connected, sendingAccepted: accepted)
            XCTAssertFalse(connection.allowsWriting)
            XCTAssertFalse(connection.sendsToOthers)
        }
        let accepted = ToolConnection(tool: .whatsapp, status: .connected, sendingAccepted: true)
        XCTAssertTrue(accepted.allowsWriting)
        XCTAssertTrue(accepted.sendsToOthers)

        // En las demás, el dato no cambia nada.
        XCTAssertTrue(ToolConnection(tool: .slack, status: .connected).sendsToOthers)
        XCTAssertFalse(ToolConnection(tool: .fireflies, status: .connected, sendingAccepted: true).allowsWriting)
    }

    /// Una instalación guardada antes de este cambio no trae el dato: se lee como «no aceptó».
    func testAConnectionSavedBeforeSendingExistedDecodesAsNotAccepted() throws {
        let old = Data(#"{"tool":"whatsapp","status":"connected","sources":{"readsEverything":true,"selected":[]}}"#.utf8)
        let connection = try JSONDecoder().decode(ToolConnection.self, from: old)
        XCTAssertNil(connection.sendingAccepted)
        XCTAssertFalse(connection.allowsWriting)

        let shared = try JSONDecoder().decode(
            SharedConnection.self, from: Data(#"{"tool":"whatsapp","status":"connected"}"#.utf8))
        XCTAssertNil(shared.sendingAccepted)
    }

    func testTranscriptionToolsAreReadOnly() {
        for tool in [Tool.fireflies, .granola, .fathom, .googleMeet] {
            XCTAssertFalse(tool.allowsWriting, "\(tool) debe ser de solo lectura")
        }
    }

    func testTheToolsThatWriteAreExactlyTheExpectedOnes() {
        let writers = Tool.allCases.filter(\.allowsWriting)

        XCTAssertEqual(
            writers, [.whatsapp, .slack, .notion, .googleWorkspace, .gmail, .jira, .claudeDesign, .googleCalendar])
    }

    func testWhatsAppConnectsByQRAndTheRestByOAuth() {
        XCTAssertEqual(Tool.whatsapp.connectionMethod, .qrCode)

        for tool in Tool.allCases where tool != .whatsapp {
            XCTAssertEqual(tool.connectionMethod, .oauth, "\(tool)")
        }
    }

    /// Google Meet no tiene MCP propio: sus transcripciones caen en Drive.
    func testGoogleMeetNeedsGoogleWorkspace() {
        XCTAssertEqual(Tool.googleMeet.requires, [.googleWorkspace])
    }

    func testOnlyGoogleMeetDependsOnAnotherTool() {
        let dependent = Tool.allCases.filter { !$0.requires.isEmpty }

        XCTAssertEqual(dependent, [.googleMeet])
    }

    func testTranscriptionToolsHaveNoSelectableSources() {
        for tool in [Tool.fireflies, .granola, .fathom] {
            XCTAssertTrue(tool.selectableSourceKinds.isEmpty, "\(tool)")
        }
    }

    func testEveryOtherToolHasSelectableSources() {
        let withoutSources = Tool.allCases.filter(\.selectableSourceKinds.isEmpty)

        // Claude Design tampoco tiene fuentes que elegir: el agente abre el enlace o el proyecto que le den.
        XCTAssertEqual(withoutSources, [.fireflies, .granola, .fathom, .claudeDesign, .googleCalendar])
    }

    func testEveryToolHasADisplayNameInBothLanguages() {
        for tool in Tool.allCases {
            for language in Language.allCases {
                XCTAssertFalse(tool.displayName(in: language).isEmpty, "\(tool) en \(language)")
            }
        }
    }

    /// Google Workspace es el único cuyo nombre cambia de idioma; el resto son
    /// marcas. Una vez salió "Docs y Sheets" dentro de un AGENTS.md en inglés.
    func testOnlyGoogleWorkspaceChangesNameByLanguage() {
        let translated = Tool.allCases.filter {
            $0.displayName(in: .spanish) != $0.displayName(in: .english)
        }

        XCTAssertEqual(translated, [.googleWorkspace])
    }

    /// Lo que le llega a otras personas: un mensaje, un correo, o un evento del calendario (los invitados).
    func testExternalSendIsOnlyWhatsAppSlackGmailAndCalendar() {
        let senders = Tool.allCases.filter { $0.externalSend != nil }

        XCTAssertEqual(senders, [.whatsapp, .slack, .gmail, .googleCalendar])
        XCTAssertEqual(Tool.whatsapp.externalSend, .whatsappMessage)
        XCTAssertEqual(Tool.googleCalendar.externalSend, .calendarEvent)
        XCTAssertEqual(Tool.slack.externalSend, .slackMessage)
        XCTAssertEqual(Tool.gmail.externalSend, .email)
    }

    func testEveryInternalWriteBelongsToExactlyOneTool() {
        for write in InternalWrite.allCases {
            let owners = Tool.allCases.filter { $0.internalWrites.contains(write) }
            XCTAssertEqual(owners.count, 1, "\(write) debería tener una sola herramienta")
        }
        XCTAssertEqual(Tool.googleWorkspace.internalWrites, [.googleDocs, .googleSheets])
    }

    /// Una herramienta que escribe tiene que tener un destino declarado, o el
    /// generador no sabría qué permiso ponerle.
    func testEveryWritingToolDeclaresWhereItWrites() {
        for tool in Tool.allCases where tool.allowsWriting {
            XCTAssertTrue(
                tool.externalSend != nil || !tool.internalWrites.isEmpty,
                "\(tool) escribe pero no declara dónde"
            )
        }
    }

    /// Los raw values son el contrato con las configs ya guardadas en disco.
    func testRawValuesAreStable() {
        XCTAssertEqual(
            Tool.allCases.map(\.rawValue),
            [
                "whatsapp", "slack", "notion", "google-workspace", "gmail",
                "jira", "fireflies", "granola", "fathom", "google-meet", "claude-design",
                "google-calendar",
            ]
        )
    }

    func testSourceKindRawValuesAreStable() {
        XCTAssertEqual(
            SourceKind.allCases.map(\.rawValue),
            ["channel", "group", "chat", "page", "database", "folder", "project", "mail-label"]
        )
    }

    func testSourceSelectionShortcuts() {
        XCTAssertTrue(SourceSelection.everything.readsEverything)
        XCTAssertTrue(SourceSelection.everything.selected.isEmpty)

        XCTAssertFalse(SourceSelection.nothing.readsEverything)
        XCTAssertTrue(SourceSelection.nothing.selected.isEmpty)

        let source = Source(id: "C1", name: "#general", kind: .channel)
        XCTAssertEqual(SourceSelection.only([source]).selected, [source])
        XCTAssertFalse(SourceSelection.only([source]).readsEverything)
    }

    func testANewConnectionReadsNothingUntilTheUserChooses() {
        let connection = ToolConnection(tool: .slack)

        XCTAssertEqual(connection.status, .selected)
        XCTAssertFalse(connection.sources.readsEverything)
        XCTAssertTrue(connection.sources.selected.isEmpty)
    }
}
