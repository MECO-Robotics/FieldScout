import Combine
import Darwin
import Foundation
import Network

struct PortalSubmission: Decodable, Sendable {
    let submissionId: String
    let fields: [String: String]
}

enum ScoutingPortalContract {
    static func payload(from data: Data) throws -> String {
        let submission = try JSONDecoder().decode(PortalSubmission.self, from: data)
        guard !submission.submissionId.isEmpty, submission.submissionId.count <= 128 else {
            throw PortalError.invalid("The scouting entry is missing its submission ID.")
        }
        guard Set(submission.fields.keys) == Set(QRScoutSchema.fieldIdentifiers) else {
            throw PortalError.invalid("The scouting entry does not contain the exact 29 QRScout fields.")
        }
        var sanitized: [String: String] = [:]
        var totalLength = 0
        for identifier in QRScoutSchema.fieldIdentifiers {
            let value = (submission.fields[identifier] ?? "")
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count <= 2_000 else {
                throw PortalError.invalid("Field \(identifier) is too long.")
            }
            totalLength += value.count
            sanitized[identifier] = value
        }
        guard totalLength <= 20_000 else {
            throw PortalError.invalid("The scouting entry is too large.")
        }
        guard Int(sanitized["mn"] ?? "") != nil, Int(sanitized["tn"] ?? "") != nil else {
            throw PortalError.invalid("Match number and team number are required.")
        }
        let envelope: [String: Any] = ["v": 2, "fields": sanitized]
        let encoded = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return ScanPayloadService.qrScoutEnvelopePrefix + encoded
    }
}

enum PortalError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

private struct PortalRequest: Sendable {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

private struct PortalResponse: Sendable {
    let status: Int
    let contentType: String
    let body: Data

    static func json(status: Int, _ value: [String: String]) -> PortalResponse {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return PortalResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }
}

private final class PortalConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let onRequest: @Sendable (PortalRequest, @escaping @Sendable (PortalResponse) -> Void) -> Void
    private var buffer = Data()
    private let maximumBytes = 64 * 1_024

    init(
        connection: NWConnection,
        onRequest: @escaping @Sendable (PortalRequest, @escaping @Sendable (PortalResponse) -> Void) -> Void
    ) {
        self.connection = connection
        self.onRequest = onRequest
    }

    func start(on queue: DispatchQueue) {
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [self] data, _, isComplete, error in
            if let data { buffer.append(data) }
            guard buffer.count <= maximumBytes else {
                send(.json(status: 413, ["message": "The scouting entry is too large."]))
                return
            }
            if let request = parseRequest(buffer) {
                onRequest(request) { [self] response in send(response) }
            } else if isComplete || error != nil {
                send(.json(status: 400, ["message": "FieldScout could not read this request."]))
            } else {
                receive()
            }
        }
    }

    private func parseRequest(_ data: Data) -> PortalRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength >= 0, contentLength <= maximumBytes else { return nil }
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        let path = requestParts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        return PortalRequest(method: requestParts[0], path: path, headers: headers, body: body)
    }

    private func send(_ response: PortalResponse) {
        let reason: String = switch response.status {
        case 200: "OK"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        case 415: "Unsupported Media Type"
        default: "Unprocessable Content"
        }
        let header = """
        HTTP/1.1 \(response.status) \(reason)\r
        Content-Type: \(response.contentType)\r
        Content-Length: \(response.body.count)\r
        Cache-Control: no-store\r
        Referrer-Policy: no-referrer\r
        X-Content-Type-Options: nosniff\r
        X-Frame-Options: DENY\r
        Connection: close\r
        \r

        """
        var data = Data(header.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { [connection] _ in connection.cancel() })
    }
}

@MainActor
final class LocalScoutingServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var urls: [String] = []
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var acceptedCount = 0
    @Published private(set) var lastSubmission = "Waiting for the first iPad"
    @Published private(set) var errorMessage: String?

    let requestedPort: UInt16
    private let store: SpreadsheetStore
    private let pageData: Data?
    private let networkQueue = DispatchQueue(label: "org.mecorobotics.fieldscout.portal", qos: .userInitiated)
    private var listener: NWListener?

    init(store: SpreadsheetStore, port: UInt16 = 8_324, pageData: Data? = nil) {
        self.store = store
        requestedPort = port
        self.pageData = pageData ?? Self.loadPortalPage()
    }

    func start() {
        guard listener == nil else { return }
        guard pageData != nil else {
            errorMessage = "The iPad Portal page is missing from this FieldScout build."
            return
        }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let port = requestedPort == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: requestedPort)!
            let listener = try NWListener(using: parameters, on: port)
            listener.service = NWListener.Service(name: "MECO FieldScout", type: "_http._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in self?.handleState(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                let handler = PortalConnection(connection: connection) { [weak self] request, reply in
                    Task { @MainActor [weak self] in self?.route(request, reply: reply) }
                }
                handler.start(on: self.networkQueue)
            }
            self.listener = listener
            listener.start(queue: networkQueue)
        } catch {
            errorMessage = "Could not start the iPad Portal: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        urls = []
    }

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .ready:
            let activePort = listener?.port?.rawValue ?? requestedPort
            port = activePort
            urls = Self.localURLs(port: activePort)
            isRunning = true
            errorMessage = urls.isEmpty ? "Connect this Mac to the same Wi-Fi network as the iPads." : nil
        case .failed(let error):
            isRunning = false
            urls = []
            errorMessage = "Could not start the iPad Portal: \(error.localizedDescription)"
            listener?.cancel()
            listener = nil
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func route(_ request: PortalRequest, reply: @escaping @Sendable (PortalResponse) -> Void) {
        if request.method == "GET", request.path == "/health" {
            reply(.json(status: 200, ["status": "ready"]))
            return
        }
        if request.method == "GET", request.path == "/" || request.path == "/index.html" {
            guard let pageData else {
                reply(.json(status: 500, ["message": "The iPad Portal page is unavailable."]))
                return
            }
            reply(PortalResponse(status: 200, contentType: "text/html; charset=utf-8", body: pageData))
            return
        }
        guard request.method == "POST", request.path == "/api/entries" else {
            reply(.json(status: 404, ["message": "Not found."]))
            return
        }
        guard request.headers["x-fieldscout-portal"] == "1", originIsAllowed(request) else {
            reply(.json(status: 403, ["message": "This submission did not come from the FieldScout iPad Portal."]))
            return
        }
        guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            reply(.json(status: 415, ["message": "FieldScout only accepts JSON scouting entries."]))
            return
        }
        do {
            let payload = try ScoutingPortalContract.payload(from: request.body)
            switch try store.ingestScan(payload) {
            case .accepted(let message):
                acceptedCount += 1
                lastSubmission = message
                reply(.json(status: 200, ["status": "accepted", "message": message]))
            case .duplicate(let message):
                lastSubmission = message
                reply(.json(status: 200, ["status": "duplicate", "message": message]))
            case .conflict(let conflict):
                store.cancelScanConflict()
                let message = "Team \(conflict.teamNumber), match \(conflict.matchNumber) already has different data. Ask the scouting lead to review it in FieldScout."
                lastSubmission = message
                reply(.json(status: 409, ["status": "conflict", "message": message]))
            }
        } catch {
            reply(.json(status: 422, ["status": "invalid", "message": error.localizedDescription]))
        }
    }

    private func originIsAllowed(_ request: PortalRequest) -> Bool {
        guard let origin = request.headers["origin"] else { return true }
        guard let host = request.headers["host"] else { return false }
        return origin == "http://\(host)"
    }

    private static func loadPortalPage() -> Data? {
        if let bundled = Bundle.main.url(forResource: "ScoutingPortal", withExtension: "html"),
           let data = try? Data(contentsOf: bundled) {
            return data
        }
        let repositoryPage = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Shared/ScoutingPortal.html")
        return try? Data(contentsOf: repositoryPage)
    }

    private static func localURLs(port: UInt16) -> [String] {
        var results = Set<String>()
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&addressPointer) == 0, let first = addressPointer {
            defer { freeifaddrs(addressPointer) }
            var pointer: UnsafeMutablePointer<ifaddrs>? = first
            while let current = pointer {
                let interface = current.pointee
                if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                   (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                   (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                    var address = interface.ifa_addr.pointee
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(&address, socklen_t(address.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let value = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        if !value.hasPrefix("169.254.") { results.insert("http://\(value):\(port)") }
                    }
                }
                pointer = interface.ifa_next
            }
        }
        let hostname = ProcessInfo.processInfo.hostName
        if !hostname.isEmpty { results.insert("http://\(hostname):\(port)") }
        return results.sorted()
    }
}
