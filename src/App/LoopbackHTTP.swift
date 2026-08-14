import Foundation
import Network

/// Loopback HTTP/1.1 listener for the Immersive Translate Custom API (ADR 0011).
/// Binds `127.0.0.1` / `::1` only. Translation still goes through `AppRuntime`.
public final class LoopbackHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let translate: @MainActor @Sendable (String, LanguagePair) async throws -> String

    public init(
        port: UInt16,
        translate: @escaping @MainActor @Sendable (String, LanguagePair) async throws -> String
    ) throws {
        self.translate = translate
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw TranslationEngineError.unavailable("bad http port: \(port)")
        }
        listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.start(queue: .global(qos: .userInitiated))
        httpLog("listen http://127.0.0.1:\(port)/")
    }

    public func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data, !data.isEmpty { next.append(data) }
            if next.count > 1_048_576 {
                self.reply(connection, status: 413, body: Data("{\"error\":\"too large\"}".utf8))
                return
            }
            if let parsed = HTTPRequest.parse(next, complete: isComplete) {
                Task { await self.handle(parsed, on: connection) }
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.read(connection, buffer: next)
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) async {
        let method = request.method.uppercased()
        if method == "OPTIONS" {
            reply(connection, status: 204, body: Data())
            return
        }
        guard method == "POST" else {
            reply(connection, status: 405, body: Data("{\"error\":\"method not allowed\"}".utf8))
            return
        }
        httpLog(
            "post \(request.body.count) bytes hex[\(HTTPPayload.hexPrefix(request.body))]"
        )
        let result = await ImmersiveTranslate.handlePOST(body: request.body) { text, pair in
            try await self.translate(text, pair)
        }
        httpLog("status \(result.status)")
        reply(connection, status: result.status, body: result.body)
    }

    private func reply(_ connection: NWConnection, status: Int, body: Data) {
        let reason = status == 200 ? "OK" : status == 204 ? "No Content" : "Error"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: POST, OPTIONS\r\n"
        head += "Access-Control-Allow-Headers: *\r\n"
        head += "Access-Control-Allow-Private-Network: true\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

struct HTTPRequest: Equatable {
    var method: String
    var body: Data

    static func parse(_ data: Data, complete: Bool = false) -> HTTPRequest? {
        let crlf = Data("\r\n\r\n".utf8)
        let lf = Data("\n\n".utf8)
        let range: Range<Data.Index>
        let lineBreak: String
        if let found = data.range(of: crlf) {
            range = found
            lineBreak = "\r\n"
        } else if let found = data.range(of: lf) {
            range = found
            lineBreak = "\n"
        } else {
            return nil
        }
        let headerData = data[..<range.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: lineBreak)
        guard let requestLine = lines.first else { return nil }
        let method = requestLine.split(separator: " ").first.map(String.init) ?? ""
        var contentLength: Int?
        var chunked = false
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
            if name == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            if name == "transfer-encoding", value.contains("chunked") {
                chunked = true
            }
        }
        let rawBody = data[range.upperBound...]
        let slice: Data
        if let contentLength {
            guard rawBody.count >= contentLength else { return nil }
            slice = Data(rawBody.prefix(contentLength))
        } else if complete || chunked {
            if chunked, let decoded = decodeChunked(Data(rawBody)) {
                return HTTPRequest(method: method, body: decoded)
            }
            if chunked, !complete { return nil }
            guard complete else { return nil }
            slice = Data(rawBody)
        } else {
            return nil
        }
        if chunked, let decoded = decodeChunked(slice) {
            return HTTPRequest(method: method, body: decoded)
        }
        return HTTPRequest(method: method, body: slice)
    }

    static func decodeChunked(_ data: Data) -> Data? {
        let crlf = Data("\r\n".utf8)
        var i = data.startIndex
        var out = Data()
        while i < data.endIndex {
            guard let lineEnd = data[i...].range(of: crlf) else { return nil }
            let sizeField = String(data: data[i..<lineEnd.lowerBound], encoding: .utf8)?
                .split(separator: ";").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let size = Int(sizeField, radix: 16) else { return nil }
            i = lineEnd.upperBound
            if size == 0 { return out }
            let end = data.index(i, offsetBy: size, limitedBy: data.endIndex)
            guard let end, end <= data.endIndex else { return nil }
            out.append(data[i..<end])
            i = end
            if data[i...].starts(with: crlf) {
                i = data.index(i, offsetBy: 2)
            }
        }
        return nil
    }
}

private func httpLog(_ message: String) {
    FileHandle.standardError.write(Data("immersive http \(message)\n".utf8))
}
