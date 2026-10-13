import XCTest
@testable import FieldScout

final class ScanPayloadServiceTests: XCTestCase {
    func testParsesNamedScannerPayload() throws {
        let result = try ScanPayloadService.parse("team=254;match=12;brokeDown=no")

        XCTAssertEqual(result, .named([
            ("team", "254"),
            ("match", "12"),
            ("brokeDown", "no")
        ]))
    }

    func testParsesJSONScannerPayload() throws {
        let result = try ScanPayloadService.parse("{\"Team\":254,\"Broke Down\":false}")

        XCTAssertEqual(result, .named([
            ("Broke Down", "No"),
            ("Team", "254")
        ]))
    }

    func testParsesCSVScannerPayloadInSheetOrder() throws {
        let result = try ScanPayloadService.parse("Alex,12,254,\"Fast, reliable\"")

        XCTAssertEqual(result, .positional(["Alex", "12", "254", "Fast, reliable"]))
    }

    func testNormalizesPrintableScannerTabAliases() throws {
        let values = (0..<QRScoutSchema.fieldCount).map(String.init)

        XCTAssertEqual(
            try ScanPayloadService.parse(values.joined(separator: "<TAB>")),
            .qrScoutLegacy(values)
        )
        XCTAssertEqual(
            try ScanPayloadService.parse(values.joined(separator: "\\t")),
            .qrScoutLegacy(values)
        )
    }

    func testParsesLegacyKeyboardSafeQRScoutEnvelope() throws {
        let values = (0..<QRScoutSchema.fieldCount).map { "field \($0) — value" }
        let tabPayload = values.joined(separator: "\t")
        let base64URL = Data(tabPayload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let payload = ScanPayloadService.legacyQRScoutEnvelopePrefix + base64URL

        XCTAssertEqual(try ScanPayloadService.parse(payload), .qrScoutLegacy(values))
        XCTAssertTrue(ScanPayloadService.isCompleteAutomaticScan(payload))
    }

    func testVersionTwoEnvelopeUsesStableFieldIdentitiesInsteadOfDictionaryOrder() throws {
        let expected = (0..<QRScoutSchema.fieldCount).map { "field \($0) — value" }
        var fields: [String: String] = [:]
        for index in QRScoutSchema.fieldIdentifiers.indices.reversed() {
            fields[QRScoutSchema.fieldIdentifiers[index]] = expected[index]
        }
        let data = try JSONSerialization.data(withJSONObject: ["v": 2, "fields": fields])
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let payload = ScanPayloadService.qrScoutEnvelopePrefix + encoded

        XCTAssertEqual(try ScanPayloadService.parse(payload), .qrScoutLegacy(expected))
        XCTAssertTrue(ScanPayloadService.isCompleteAutomaticScan(payload))
    }

    func testVersionTwoEnvelopeRejectsMissingFieldsInsteadOfShiftingColumns() throws {
        let data = try JSONSerialization.data(withJSONObject: ["v": 2, "fields": ["teamNumber": "8324"]])
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        XCTAssertThrowsError(try ScanPayloadService.parse(ScanPayloadService.qrScoutEnvelopePrefix + encoded))
    }

    func testPartialLegacyScanDoesNotAutoCommit() {
        let partial = (0..<8).map(String.init).joined(separator: "\t")
        let complete = (0..<QRScoutSchema.fieldCount).map(String.init).joined(separator: "\t")

        XCTAssertTrue(ScanPayloadService.isPackedRow(partial))
        XCTAssertFalse(ScanPayloadService.isCompleteAutomaticScan(partial))
        XCTAssertTrue(ScanPayloadService.isCompleteAutomaticScan(complete))
    }

    func testOnlyMultiFieldRowsAreRecognizedAsPackedScans() {
        XCTAssertFalse(ScanPayloadService.isPackedRow("Fast, stable"))
        XCTAssertTrue(ScanPayloadService.isPackedRow((0..<29).map(String.init).joined(separator: "\t")))
    }

    func testRejectsUnknownPackedPayloadInsteadOfDroppingIt() {
        XCTAssertThrowsError(try ScanPayloadService.parse("UNKNOWNPACKEDVALUE")) { error in
            XCTAssertEqual(error as? ScanPayloadError, .unsupported)
        }
    }
}
