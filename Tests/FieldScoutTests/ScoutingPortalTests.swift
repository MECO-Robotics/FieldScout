import Foundation
import XCTest
@testable import FieldScout

final class ScoutingPortalTests: XCTestCase {
    private func sampleFields() -> [String: String] {
        var fields = Dictionary(uniqueKeysWithValues: QRScoutSchema.fieldIdentifiers.enumerated().map { index, identifier in
            (identifier, "field-\(index)")
        })
        fields["si"] = "AJ"
        fields["mn"] = "12"
        fields["tn"] = "8324"
        fields["sp"] = "Outpost Trench"
        fields["ns"] = "false"
        fields["ecl"] = "L3"
        return fields
    }

    func testPortalSubmissionMapsAllNamedFieldsToCanonicalColumns() throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "submissionId": "entry-1",
            "fields": sampleFields()
        ])
        let payload = try ScoutingPortalContract.payload(from: body)
        guard case .qrScoutLegacy(let parsed) = try ScanPayloadService.parse(payload) else {
            return XCTFail("Portal did not create a QRScout payload")
        }

        XCTAssertTrue(payload.hasPrefix("QRSCOUT2-"))
        XCTAssertEqual(parsed.count, 29)
        XCTAssertEqual(parsed[0], "AJ")
        XCTAssertEqual(parsed[1], "12")
        XCTAssertEqual(parsed[2], "8324")
        XCTAssertEqual(parsed[3], "Outpost Trench")
        XCTAssertEqual(parsed[15], "L3")
    }

    func testPortalRejectsMissingFieldInsteadOfShiftingColumns() throws {
        var fields = sampleFields()
        fields.removeValue(forKey: "afs")
        let body = try JSONSerialization.data(withJSONObject: [
            "submissionId": "entry-2",
            "fields": fields
        ])

        XCTAssertThrowsError(try ScoutingPortalContract.payload(from: body)) { error in
            XCTAssertTrue(error.localizedDescription.contains("exact 29"))
        }
    }

    @MainActor
    func testPortalPayloadCreatesExactlyOneEntryAndOneBlankRow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpreadsheetStore(storageDirectory: directory)
        let body = try JSONSerialization.data(withJSONObject: [
            "submissionId": "entry-3",
            "fields": sampleFields()
        ])

        let result = try store.ingestScan(ScoutingPortalContract.payload(from: body))

        guard case .accepted = result else { return XCTFail("Portal entry was not accepted") }
        XCTAssertEqual(store.meaningfulRowCount, 1)
        XCTAssertEqual(store.document.rows.count, 2)
        XCTAssertEqual(store.document.rows[0].values[store.document.columns[2].id], "8324")
        XCTAssertTrue(store.document.rows[1].values.values.allSatisfy { $0.isEmpty })
    }

    func testPortalPageContainsEveryQRScoutFieldIdentifier() throws {
        let pageURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Shared/ScoutingPortal.html")
        let page = try String(contentsOf: pageURL, encoding: .utf8)

        for identifier in QRScoutSchema.fieldIdentifiers {
            XCTAssertTrue(
                page.contains("id=\"\(identifier)\"") || page.contains("data-multi=\"\(identifier)\""),
                "Portal is missing \(identifier)"
            )
        }
    }

    @MainActor
    func testLocalPortalHTTPServerMovesOneEntryIntoTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpreadsheetStore(storageDirectory: directory)
        let page = Data("<html><body>FieldScout test portal</body></html>".utf8)
        let server = LocalScoutingServer(store: store, port: 0, pageData: page)
        server.start()
        defer { server.stop() }

        for _ in 0..<100 where !server.isRunning {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(server.isRunning)
        XCTAssertGreaterThan(server.port, 0)
        let base = "http://127.0.0.1:\(server.port)"

        let (healthData, healthResponse) = try await URLSession.shared.data(from: URL(string: "\(base)/health")!)
        XCTAssertEqual((healthResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: healthData, as: UTF8.self), "{\"status\":\"ready\"}")

        let body = try JSONSerialization.data(withJSONObject: [
            "submissionId": "live-entry",
            "fields": sampleFields()
        ])
        var request = URLRequest(url: URL(string: "\(base)/api/entries")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-FieldScout-Portal")
        request.setValue(base, forHTTPHeaderField: "Origin")
        let (responseData, response) = try await URLSession.shared.data(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, String(decoding: responseData, as: UTF8.self))
        XCTAssertEqual(store.meaningfulRowCount, 1)
        XCTAssertEqual(store.document.rows.count, 2)
        XCTAssertEqual(store.document.rows[0].values[store.document.columns[2].id], "8324")
        XCTAssertEqual(server.acceptedCount, 1)
    }
}
