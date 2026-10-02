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

    func testEveryToolHasADisplayName() {
        for tool in Tool.allCases {
            XCTAssertFalse(tool.displayName.isEmpty, "\(tool)")
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
