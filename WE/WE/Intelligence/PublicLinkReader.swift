import Foundation
import Network
import Security
import Darwin

/// HTTPS over a pinned, validated public address. DNS is never resolved again
/// between the public-address check and the connection. No cookies or redirects.
nonisolated enum WEPublicLinkReader {
    enum Failure: Error { case unsafeURL, address, response, tooLarge, timeout }
    static func permits(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
              !host.contains(":"), !host.hasSuffix(".local"), host != "localhost" else { return false }
        let sensitive = ["token", "key", "auth", "signature", "password", "code", "session"]
        return !(parts.queryItems ?? []).contains { item in sensitive.contains { item.name.lowercased().contains($0) } }
    }
    static func permitsAutomatic(_ url: URL) -> Bool {
        guard permits(url), url.query == nil, url.fragment == nil else { return false }
        // Opaque identifiers may carry invitations or credentials. Ask explicitly.
        return !url.pathComponents.contains { component in
            component.count > 24 && component.rangeOfCharacter(from: .decimalDigits) != nil
        }
    }
    static func publicIPv4(_ address: String) -> Bool {
        let p = address.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }) else { return false }
        return p[0] != 0 && p[0] != 10 && p[0] != 127 && p[0] < 224
            && !(p[0] == 169 && p[1] == 254) && !(p[0] == 172 && (16...31).contains(p[1]))
            && !(p[0] == 192 && (p[1] == 168 || p[1] == 0))
            && !(p[0] == 100 && (64...127).contains(p[1]))
            && !(p[0] == 198 && (18...19).contains(p[1]))
    }
    static func read(_ url: URL) async throws -> String {
        guard permits(url), let host = url.host else { throw Failure.unsafeURL }
        // IPv4-only is a conservative first-release limitation, never a reason
        // to fall back to an unchecked DNS/HTTP client.
        let address = try await Task.detached { () throws -> String in
            var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, "443", &hints, &result) == 0, let first = result else { throw Failure.address }
            defer { freeaddrinfo(first) }
            var current: UnsafeMutablePointer<addrinfo>? = first
            var addresses: [String] = []
            while let row = current {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(row.pointee.ai_addr, row.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { throw Failure.address }
                let value = String(cString: buffer)
                guard publicIPv4(value) else { throw Failure.address }
                addresses.append(value); current = row.pointee.ai_next
            }
            guard let address = addresses.first else { throw Failure.address }; return address
        }.value
        try Task.checkCancellation()
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let path = (parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath) + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
        let request = "GET \(path) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\nAccept: text/html,text/plain\r\nAccept-Encoding: identity\r\nUser-Agent: WE-LinkUnderstanding/1\r\n\r\n"
        let transport = WEPublicHTTPSConnection(address: address, serverName: host)
        let data = try await withTaskCancellationHandler {
            try await transport.read(Data(request.utf8))
        } onCancel: { transport.cancel() }
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: data[..<separator.lowerBound], encoding: .utf8),
              header.hasPrefix("HTTP/1.1 200") || header.hasPrefix("HTTP/1.0 200") else { throw Failure.response }
        let lower = header.lowercased()
        guard lower.contains("content-type: text/html") || lower.contains("content-type: text/plain"),
              !lower.contains("content-encoding:") || lower.contains("content-encoding: identity") else { throw Failure.response }
        var bytes = Data(data[separator.upperBound...])
        if lower.contains("transfer-encoding: chunked") { bytes = try unchunk(bytes) }
        guard var text = String(data: bytes, encoding: .utf8) else { throw Failure.response }
        if lower.contains("text/html") {
            for pattern in ["(?is)<script\\b[^>]*>.*?</script>", "(?is)<style\\b[^>]*>.*?</style>", "(?s)<[^>]+>"] {
                text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            }
            for (entity, replacement) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&nbsp;", " ")] {
                text = text.replacingOccurrences(of: entity, with: replacement)
            }
        }
        return String(text.prefix(20_000))
    }
    private static func unchunk(_ data: Data) throws -> Data {
        var rest = data; var output = Data()
        while let end = rest.range(of: Data("\r\n".utf8)) {
            guard let line = String(data: rest[..<end.lowerBound], encoding: .ascii),
                  let sizeText = line.split(separator: ";").first,
                  let size = Int(sizeText, radix: 16), size >= 0, size <= 1_048_576 else { throw Failure.response }
            rest = Data(rest[end.upperBound...])
            if size == 0 { return output }
            guard rest.count >= size + 2 else { throw Failure.response }
            output.append(rest.prefix(size)); rest = Data(rest.dropFirst(size + 2))
        }
        throw Failure.response
    }
}

nonisolated private final class WEPublicHTTPSConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "we.public-link")
    private var continuation: CheckedContinuation<Data, Error>?
    private var received = Data()
    private var cancelled = false
    init(address: String, serverName: String) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, serverName)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        connection = NWConnection(host: NWEndpoint.Host(address), port: 443, using: NWParameters(tls: tls))
    }
    func read(_ request: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if self.cancelled { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                self.connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        self.connection.send(content: request, completion: .contentProcessed { error in
                            if let error { self.finish(.failure(error)) } else { self.receive() }
                        })
                    case .failed(let error): self.finish(.failure(error))
                    default: break
                    }
                }
                self.connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 20) { self.finish(.failure(WEPublicLinkReader.Failure.timeout)) }
            }
        }
    }
    func cancel() { queue.async { self.cancelled = true; self.finish(.failure(CancellationError())) } }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { data, _, complete, error in
            if let data { self.received.append(data) }
            if self.received.count > 1_048_576 { self.finish(.failure(WEPublicLinkReader.Failure.tooLarge)) }
            else if let error { self.finish(.failure(error)) }
            else if complete { self.finish(.success(self.received)) }
            else { self.receive() }
        }
    }
    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil; connection.stateUpdateHandler = nil; connection.cancel()
        continuation.resume(with: result)
    }
}
