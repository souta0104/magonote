import Foundation
@testable import MagonoteKit

/// Header used to route a stubbed request to the handler registered for the
/// `URLSession` that sent it, so tests can run concurrently without sharing
/// mutable state across unrelated requests.
private let stubIDHeaderField = "X-MagonoteKitTests-Stub-Id"

/// A `URLProtocol` stub that intercepts every request made through a session
/// configured with it, and dispatches to the handler registered for that
/// session's stub id (see `withStubbedClient`). Handler storage is guarded by
/// a lock so concurrently-running tests never observe each other's handlers.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func register(id: String, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[id] = handler
    }

    static func unregister(id: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers[id] = nil
    }

    private static func handler(for id: String) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[id]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let id = request.value(forHTTPHeaderField: stubIDHeaderField),
            let handler = StubURLProtocol.handler(for: id)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Thread-safe capture of the last request seen by a `StubURLProtocol` handler,
/// so assertions can happen back on the test's own task after `await`.
final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: URLRequest?

    func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        _request = request
    }

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _request
    }
}

struct StubTokenProvider: AuthTokenProvider {
    let token: String

    func idToken() async throws -> String {
        token
    }
}

/// Registers a stub handler for the lifetime of `body` and always unregisters it
/// afterwards, so the static handler table never grows across the test suite.
func withStubbedClient<R>(
    baseURL: URL = URL(string: "https://api.magonote.example")!,
    token: String = "stub-token",
    handler: @escaping StubURLProtocol.Handler,
    _ body: (MagonoteAPIClient) async throws -> R
) async rethrows -> R {
    let stubID = UUID().uuidString
    StubURLProtocol.register(id: stubID, handler: handler)
    defer { StubURLProtocol.unregister(id: stubID) }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    configuration.httpAdditionalHeaders = [stubIDHeaderField: stubID]
    let session = URLSession(configuration: configuration)

    let client = MagonoteAPIClient(
        baseURL: baseURL,
        tokenProvider: StubTokenProvider(token: token),
        session: session
    )
    return try await body(client)
}

func jsonResponse(url: URL, statusCode: Int, object: [String: Any?]) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    let sanitized = object.mapValues { $0 ?? NSNull() }
    let data = try! JSONSerialization.data(withJSONObject: sanitized)
    return (response, data)
}

func errorEnvelope(url: URL, statusCode: Int, code: String, message: String) -> (HTTPURLResponse, Data) {
    jsonResponse(url: url, statusCode: statusCode, object: ["error": ["code": code, "message": message]])
}

let sampleCapturedAtMillis: Int64 = 1_700_000_000_000
let sampleCreatedAtMillis: Int64 = 1_700_000_100_000

func documentJSONObject(
    id: String = "doc-1",
    text: String = "hello world",
    sourceAppName: String = "Xcode",
    sourceMachineName: String = "MacBook-Pro",
    capturedAt: Int64 = sampleCapturedAtMillis,
    createdAt: Int64 = sampleCreatedAtMillis,
    archivedAt: Int64? = nil
) -> [String: Any?] {
    [
        "id": id,
        "text": text,
        "sourceAppName": sourceAppName,
        "sourceMachineName": sourceMachineName,
        "capturedAt": capturedAt,
        "createdAt": createdAt,
        "archivedAt": archivedAt as Any?,
    ]
}
