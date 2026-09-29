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
    static func parse(_ rawPayload: String) throws -> ParsedScan {
        // Preserve leading and trailing tabs because empty first/last QRScout fields are significant.
        let payload = rawPayload.trimmingCharacters(in: CharacterSet(charactersIn: " \r\n"))
        guard !payload.isEmpty else { throw ScanPayloadError.empty }

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
}
