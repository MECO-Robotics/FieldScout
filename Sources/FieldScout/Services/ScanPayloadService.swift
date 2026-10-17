import Foundation

enum ScanPayloadError: LocalizedError, Equatable {
    case empty
    case unsupported

    var errorDescription: String? {
        switch self {
        case .empty:
            return "The scanner did not send any data."
        case .unsupported:
            return "This barcode format is not recognized yet. Use JSON, key=value pairs, CSV, or tab-separated values."
        }
    }
}

enum ParsedScan: Equatable {
    case named([(String, String)])
    case positional([String])
    case qrScoutLegacy([String])

    static func == (lhs: ParsedScan, rhs: ParsedScan) -> Bool {
        switch (lhs, rhs) {
        case let (.named(left), .named(right)):
            return left.elementsEqual(right, by: ==)
        case let (.positional(left), .positional(right)):
            return left == right
        case let (.qrScoutLegacy(left), .qrScoutLegacy(right)):
            return left == right
        default:
            return false
        }
    }
}

enum ScanPayloadService {
    static let compactQRScoutEnvelopePrefix = "QRSCOUT3-"
    static let qrScoutEnvelopePrefix = "QRSCOUT2-"
    static let legacyQRScoutEnvelopePrefix = "QRSCOUT1-"

    static func normalizedPayload(_ rawPayload: String) -> String {
        var payload = rawPayload.trimmingCharacters(in: CharacterSet(charactersIn: " \r\n"))
        guard !payload.isEmpty, payload.first != "{" else { return payload }

        // Some keyboard-wedge scanners send a printable stand-in for Tab instead of
        // the control character contained in the QR code. Treat the common variants
        // as field separators so the entire scan cannot get stranded in one cell.
        let separatorAliases = ["\\t", "<TAB>", "⇥", "\u{000B}", "\u{001D}", "\u{001E}", "\u{001F}"]
        for alias in separatorAliases {
            payload = payload.replacingOccurrences(
                of: alias,
                with: "\t",
                options: alias == "<TAB>" ? [.caseInsensitive] : []
            )
        }
        return payload
    }

    static func isPackedRow(_ rawPayload: String) -> Bool {
        guard let parsed = try? parse(rawPayload) else { return false }
        switch parsed {
        case .qrScoutLegacy:
            return true
        case .positional(let fields):
            return fields.count >= 8
        case .named(let fields):
            return fields.count >= 2
        }
    }

    /// Only complete, self-identifying QRScout records may be committed after an
    /// idle pause. Generic rows still require Return or the Add Scan button because
    /// their final field count is unknown.
    static func isCompleteAutomaticScan(_ rawPayload: String) -> Bool {
        guard let parsed = try? parse(rawPayload) else { return false }
        if case .qrScoutLegacy = parsed { return true }
        return false
    }

    static func parse(_ rawPayload: String) throws -> ParsedScan {
        // Preserve leading and trailing tabs because empty first/last QRScout fields are significant.
        let payload = normalizedPayload(rawPayload)
        guard !payload.isEmpty else { throw ScanPayloadError.empty }

        if payload.hasPrefix(compactQRScoutEnvelopePrefix) {
            let encoded = String(payload.dropFirst(compactQRScoutEnvelopePrefix.count))
            guard let data = decodeBase64URL(encoded),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let compactFields = object as? [Any],
                  let fields = QRScoutSchema.expandedCompactValues(compactFields) else {
                throw ScanPayloadError.unsupported
            }
            return .qrScoutLegacy(fields)
        }

        if payload.hasPrefix(qrScoutEnvelopePrefix) {
            let encoded = String(payload.dropFirst(qrScoutEnvelopePrefix.count))
            guard let data = decodeBase64URL(encoded),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let envelope = object as? [String: Any],
                  (envelope["v"] as? NSNumber)?.intValue == 2,
                  let rawFields = envelope["fields"] as? [String: Any] else {
                throw ScanPayloadError.unsupported
            }
            let fieldsByIdentifier = rawFields.reduce(into: [String: String]()) { result, entry in
                result[entry.key] = stringify(entry.value)
            }
            guard let fields = QRScoutSchema.orderedValues(from: fieldsByIdentifier) else {
                throw ScanPayloadError.unsupported
            }
            return .qrScoutLegacy(fields)
        }

        if payload.hasPrefix(legacyQRScoutEnvelopePrefix) {
            let encoded = String(payload.dropFirst(legacyQRScoutEnvelopePrefix.count))
            guard let data = decodeBase64URL(encoded),
                  let decoded = String(data: data, encoding: .utf8) else {
                throw ScanPayloadError.unsupported
            }
            let fields = decoded.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == QRScoutSchema.fieldCount else {
                throw ScanPayloadError.unsupported
            }
            return .qrScoutLegacy(fields)
        }

        // A damaged or future QRScout envelope must fail closed instead of being
        // accepted as a generic row and silently shifting values into wrong cells.
        if payload.hasPrefix("QRSCOUT") { throw ScanPayloadError.unsupported }

        if payload.first == "{",
           let data = payload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            let fields = dictionary.keys.sorted().map { key in
                (key, stringify(dictionary[key]))
            }
            if !fields.isEmpty { return .named(fields) }
        }

        if payload.contains("=") {
            let chunks = payload.split(
                omittingEmptySubsequences: true,
                whereSeparator: { $0 == ";" || $0 == "|" || $0 == "\t" }
            )
            let fields = chunks.compactMap { chunk -> (String, String)? in
                guard let equals = chunk.firstIndex(of: "=") else { return nil }
                let key = chunk[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = chunk[chunk.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
                return key.isEmpty ? nil : (key, value)
            }
            if !fields.isEmpty, fields.count == chunks.count { return .named(fields) }
        }

        if payload.contains("\t") {
            let fields = payload.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if fields.count == QRScoutSchema.fieldCount {
                return .qrScoutLegacy(fields)
            }
            return .positional(fields)
        }

        if payload.contains(","), let fields = CSVService.parse(payload).first {
            return .positional(fields)
        }

        throw ScanPayloadError.unsupported
    }

    static func inferredType(for value: String) -> ColumnDataType {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "false", "yes", "no", "y", "n", "x"].contains(normalized) { return .boolean }
        if Int(normalized) != nil { return .integer }
        if Double(normalized) != nil { return .decimal }
        return .text
    }

    private static func stringify(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let string = value as? String { return string }
        if let bool = value as? Bool { return bool ? "Yes" : "No" }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return String(describing: value)
    }

    private static func decodeBase64URL(_ encoded: String) -> Data? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        return Data(base64Encoded: base64)
    }
}
