import Darwin
import Foundation

public struct ReviewServerResult: Codable, Sendable {
    public var url: String
    public var decision: ReviewDecision
}

public final class PatchReviewServer {
    private let patch: LibraryAIPatch
    private let patchData: Data
    private let validation: PatchValidationResult
    private let resultURL: URL
    private let token: String
    private let timeoutSeconds: TimeInterval
    private let lock = NSLock()

    private var serverFD: Int32 = -1
    private var completedDecision: ReviewDecision?
    private var completionContinuation: CheckedContinuation<ReviewDecision, Never>?

    public init(
        patch: LibraryAIPatch,
        patchData: Data,
        validation: PatchValidationResult,
        resultURL: URL,
        timeoutSeconds: TimeInterval = 300,
        token: String = UUID().uuidString
    ) {
        self.patch = patch
        self.patchData = patchData
        self.validation = validation
        self.resultURL = resultURL
        self.timeoutSeconds = timeoutSeconds
        self.token = token
    }

    public func run() async throws -> ReviewServerResult {
        let port = try startListening()
        let url = "http://127.0.0.1:\(port)/review?token=\(token)"
        fputs("Review URL: \(url)\n", stderr)

        let decision = await withCheckedContinuation { continuation in
            lock.lock()
            completionContinuation = continuation
            lock.unlock()

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                guard let self else { return }
                self.complete(
                    ReviewDecision(
                        approved: false,
                        rejectedAt: .now,
                        reason: "timeout",
                        patchDigest: self.validation.patchDigest
                    )
                )
            }
        }

        try FileSystem.writeJSON(decision, to: resultURL)
        stop()
        return ReviewServerResult(url: url, decision: decision)
    }

    public func startForTesting() throws -> String {
        let port = try startListening()
        return "http://127.0.0.1:\(port)/review?token=\(token)"
    }

    public func waitForTesting() async -> ReviewDecision {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let completedDecision {
                lock.unlock()
                continuation.resume(returning: completedDecision)
                return
            }
            completionContinuation = continuation
            lock.unlock()
        }
    }

    public func stopForTesting() {
        stop()
    }

    private func startListening() throws -> UInt16 {
        serverFD = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw CLIError("socket() failed")
        }

        var enabled: Int32 = 1
        setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &enabled, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw CLIError("bind(127.0.0.1) failed")
        }
        guard listen(serverFD, 16) == 0 else {
            throw CLIError("listen() failed")
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(serverFD, $0, &boundLength)
            }
        }
        guard nameResult == 0 else {
            throw CLIError("getsockname() failed")
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop()
        }

        return UInt16(bigEndian: boundAddress.sin_port)
    }

    private func acceptLoop() {
        while serverFD >= 0 {
            let connectionFD = accept(serverFD, nil, nil)
            if connectionFD < 0 {
                break
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleConnection(connectionFD)
            }
        }
    }

    private func handleConnection(_ fd: Int32) {
        defer { close(fd) }

        guard let request = readHTTPRequest(from: fd) else {
            writeResponse(status: "400 Bad Request", body: "bad request", contentType: "text/plain", to: fd)
            return
        }

        let tokenIsValid = request.query["token"] == token
        guard tokenIsValid else {
            writeResponse(status: "403 Forbidden", body: "invalid token", contentType: "text/plain", to: fd)
            return
        }

        if request.method == "GET", request.path == "/review" {
            writeResponse(status: "200 OK", body: renderHTML(), contentType: "text/html; charset=utf-8", to: fd)
        } else if request.method == "GET", request.path == "/raw.json" {
            let json = (try? String(data: HomeLibraryJSONCodec.makeEncoder().encode(patch), encoding: .utf8)) ?? "{}"
            writeResponse(status: "200 OK", body: json, contentType: "application/json", to: fd)
        } else if request.method == "POST", request.path == "/approve" {
            complete(ReviewDecision(
                approved: true,
                approvedAt: .now,
                patchDigest: validation.patchDigest,
                approvedOperationIDs: patch.operations.map(\.clientOperationID),
                includeLowConfidence: request.body.contains("includeLowConfidence=true")
            ))
            writeResponse(status: "200 OK", body: #"{"ok":true,"approved":true}"#, contentType: "application/json", to: fd)
        } else if request.method == "POST", request.path == "/reject" {
            complete(ReviewDecision(
                approved: false,
                rejectedAt: .now,
                reason: "rejected",
                patchDigest: validation.patchDigest,
                rejectedOperationIDs: patch.operations.map(\.clientOperationID)
            ))
            writeResponse(status: "200 OK", body: #"{"ok":true,"approved":false}"#, contentType: "application/json", to: fd)
        } else {
            writeResponse(status: "404 Not Found", body: "not found", contentType: "text/plain", to: fd)
        }
    }

    private func complete(_ decision: ReviewDecision) {
        lock.lock()
        if completedDecision != nil {
            lock.unlock()
            return
        }
        completedDecision = decision
        let continuation = completionContinuation
        completionContinuation = nil
        lock.unlock()

        try? FileSystem.writeJSON(decision, to: resultURL)
        continuation?.resume(returning: decision)
        stop()
    }

    private func stop() {
        lock.lock()
        let fd = serverFD
        serverFD = -1
        lock.unlock()

        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
    }

    private func renderHTML() -> String {
        let creates = patch.operations.filter { $0.opName == "createBook" }.count
        let updates = patch.operations.filter { $0.opName == "updateBook" }.count
        let coverChanges = patch.operations.filter { $0.opName == "updateBookCover" || $0.opName == "removeBookCover" }.count
        let deletes = patch.operations.filter { $0.opName == "deleteBook" }.count
        let dangerous = validation.operations.filter(\.requiresApproval)
        let rawRows = validation.operations.map { operation in
            "<tr><td>\(escape(operation.clientOperationID))</td><td>\(escape(operation.op))</td><td>\(operation.status.rawValue)</td><td>\(escape(operation.message))</td><td>\(escape(operation.risks.joined(separator: ", ")))</td></tr>"
        }.joined(separator: "\n")
        let evidence = patch.operations.flatMap(\.evidence).compactMap(\.url).map { "<li>\(escape($0))</li>" }.joined(separator: "\n")

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>home-library-cloudkit review</title>
          <style>
          body{font-family:-apple-system,BlinkMacSystemFont,Helvetica,Arial,sans-serif;margin:32px;line-height:1.4;color:#1f2933}
          table{border-collapse:collapse;width:100%;margin:16px 0}
          th,td{border:1px solid #d9e2ec;padding:8px;text-align:left;vertical-align:top}
          .danger{border:2px solid #b42318;background:#fff1f0;padding:12px;margin:16px 0}
          .actions{display:flex;gap:12px;margin-top:24px}
          button{font-size:16px;padding:10px 14px}
          </style>
        </head>
        <body>
          <h1>Patch Review</h1>
          <h2>Summary</h2>
          <ul>
            <li>Source: \(escape(patch.source))</li>
            <li>Target repository: \(escape(patch.targetRepository.id))</li>
            <li>Creates: \(creates)</li>
            <li>Updates: \(updates)</li>
            <li>Cover changes: \(coverChanges)</li>
            <li>Deletes: \(deletes)</li>
            <li>Needs review: \(validation.needsReviewCount)</li>
            <li>Conflicts: \(validation.conflictCount)</li>
            <li>Skipped: \(validation.skippedCount)</li>
          </ul>
          \(deletes > 0 || !dangerous.isEmpty ? "<div class='danger'><strong>Danger zone</strong><p>Deletes, cover removal, existing-cover replacement, non-empty field replacement, or low-confidence operations are present.</p></div>" : "")
          <h2>Creates</h2>
          <p>\(creates) create operations.</p>
          <h2>Updates</h2>
          <p>\(updates) field update operations. replaceIfCurrentValue operations require old -&gt; new review.</p>
          <h2>Deletes</h2>
          <p>\(deletes) deleteBook operations.</p>
          <h2>Cover changes</h2>
          <p>\(coverChanges) cover operations. Existing and candidate coverAssetID values are included in validation rows when available.</p>
          <h2>Conflicts / Skipped / Raw JSON</h2>
          <table><thead><tr><th>ID</th><th>Operation</th><th>Status</th><th>Message</th><th>Risks</th></tr></thead><tbody>\(rawRows)</tbody></table>
          <h2>Evidence</h2>
          <ul>\(evidence)</ul>
          <p><a href="/raw.json?token=\(token)">Raw JSON</a></p>
          <div class="actions">
            <form method="post" action="/approve?token=\(token)">
              <label><input type="checkbox" name="includeLowConfidence" value="true"> Include low confidence</label>
              <button type="submit">Approve</button>
            </form>
            <form method="post" action="/reject?token=\(token)">
              <button type="submit">Reject</button>
            </form>
          </div>
        </body>
        </html>
        """
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension PatchReviewServer: @unchecked Sendable {}

private struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var body: String
}

private func readHTTPRequest(from fd: Int32) -> HTTPRequest? {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    var headerEndRange: Range<Data.Index>?
    var contentLength = 0

    while true {
        let count = recv(fd, &buffer, buffer.count, 0)
        if count <= 0 {
            break
        }
        data.append(buffer, count: count)

        if headerEndRange == nil,
           let range = data.range(of: Data("\r\n\r\n".utf8)) {
            headerEndRange = range
            let headerData = data[..<range.lowerBound]
            let headerString = String(data: headerData, encoding: .utf8) ?? ""
            contentLength = parseContentLength(headerString)
        }

        if let headerEndRange {
            let bodyStart = headerEndRange.upperBound
            if data.count - bodyStart >= contentLength {
                break
            }
        }
    }

    guard let headerEndRange,
          let headerString = String(data: data[..<headerEndRange.lowerBound], encoding: .utf8) else {
        return nil
    }
    let lines = headerString.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else {
        return nil
    }
    let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else {
        return nil
    }

    let bodyStart = headerEndRange.upperBound
    let bodyData = bodyStart < data.count ? data[bodyStart..<data.count] : Data()
    let body = String(data: bodyData, encoding: .utf8) ?? ""
    let pathAndQuery = parts[1]
    let components = pathAndQuery.split(separator: "?", maxSplits: 1).map(String.init)
    let path = components.first ?? "/"
    let queryString = components.count > 1 ? components[1] : ""

    return HTTPRequest(
        method: parts[0],
        path: path,
        query: parseQuery(queryString),
        body: body
    )
}

private func parseContentLength(_ headerString: String) -> Int {
    for line in headerString.components(separatedBy: "\r\n") {
        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2,
           parts[0].lowercased() == "content-length" {
            return Int(parts[1].trimmed) ?? 0
        }
    }
    return 0
}

private func parseQuery(_ query: String) -> [String: String] {
    var values: [String: String] = [:]
    for pair in query.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard let key = parts.first?.removingPercentEncoding else {
            continue
        }
        values[key] = parts.count > 1 ? parts[1].removingPercentEncoding : ""
    }
    return values
}

private func writeResponse(status: String, body: String, contentType: String, to fd: Int32) {
    let bodyData = Data(body.utf8)
    let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
    var response = Data(header.utf8)
    response.append(bodyData)
    response.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            return
        }
        _ = send(fd, baseAddress, rawBuffer.count, 0)
    }
}
