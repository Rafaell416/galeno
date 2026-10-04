import Foundation
import XCTest

@testable import GalenoCore

final class SendingRulesTests: XCTestCase {
    func testExternalSendsAlwaysRequireApproval() {
        var rules = SendingRules.default
        for write in InternalWrite.allCases {
            rules.setPolicy(.allow, for: write)
        }

        for send in ExternalSend.allCases {
            XCTAssertEqual(rules.policy(for: send), .ask, "\(send) debe requerir aprobación")
        }
    }

    /// El bridge de WhatsApp no envía, así que WhatsApp ni siquiera es un envío
    /// que haya que gobernar. Si alguien añade el caso, esta prueba falla.
    func testWhatsAppIsNotAnExternalSend() {
        XCTAssertEqual(
            ExternalSend.allCases.map(\.rawValue).sorted(),
            ["calendar-event", "email", "slack-message"]
        )
    }

    func testDefaultAllowsEveryInternalWriteExceptDesign() {
        for write in InternalWrite.allCases where write != .claudeDesign {
            XCTAssertEqual(SendingRules.default.policy(for: write), .allow, "\(write)")
        }
        // Puede borrar archivos de diseño: de fábrica pregunta.
        XCTAssertEqual(SendingRules.default.policy(for: .claudeDesign), .ask)
    }

    func testAMissingInternalPolicyFallsBackToAsk() {
        let rules = SendingRules()

        for write in InternalWrite.allCases {
            XCTAssertEqual(rules.policy(for: write), .ask, "\(write)")
        }
    }

    func testSetPolicyOverridesTheDefault() {
        var rules = SendingRules.default
        rules.setPolicy(.ask, for: .jira)

        XCTAssertEqual(rules.policy(for: .jira), .ask)
        XCTAssertEqual(rules.policy(for: .notion), .allow)
    }

    /// `Dictionary` codifica como un array de claves y valores alternados
    /// cuando la clave no es `String` ni `Int`. `InternalWrite` conforma
    /// `CodingKeyRepresentable` para evitarlo; esta prueba lo verifica.
    func testInternalWritesEncodeAsAJSONObject() throws {
        var rules = SendingRules()
        rules.setPolicy(.allow, for: .notion)
        rules.setPolicy(.ask, for: .googleSheets)

        let data = try JSONEncoder().encode(rules)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let writes = try XCTUnwrap(
            object["internalWrites"] as? [String: String],
            "internalWrites debería ser un objeto JSON, no un array"
        )

        XCTAssertEqual(writes, ["notion": "allow", "google-sheets": "ask"])
    }

    func testRoundTrip() throws {
        var original = SendingRules.default
        original.setPolicy(.ask, for: .jira)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SendingRules.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testTheRedLineIsDocumentedInCode() {
        XCTAssertTrue(SendingRules.externalAlwaysRequiresApproval)
    }
}
