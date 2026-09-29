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
