import XCTest

@testable import GalenoCore

final class ToolTests: XCTestCase {
    /// Línea roja: el MCP de WhatsApp no tiene herramientas de envío.
    func testWhatsAppCannotWrite() {
        XCTAssertFalse(Tool.whatsapp.allowsWriting)
    }

    func testTranscriptionToolsAreReadOnly() {
        for tool in [Tool.fireflies, .granola, .fathom, .googleMeet] {
            XCTAssertFalse(tool.allowsWriting, "\(tool) debe ser de solo lectura")
        }
    }

    func testTheToolsThatWriteAreExactlyTheExpectedOnes() {
        let writers = Tool.allCases.filter(\.allowsWriting)

        XCTAssertEqual(writers, [.slack, .notion, .googleWorkspace, .gmail, .jira])
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

        XCTAssertEqual(withoutSources, [.fireflies, .granola, .fathom])
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

    func testExternalSendIsOnlySlackAndGmail() {
        let senders = Tool.allCases.filter { $0.externalSend != nil }

        XCTAssertEqual(senders, [.slack, .gmail])
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
                "jira", "fireflies", "granola", "fathom", "google-meet",
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
