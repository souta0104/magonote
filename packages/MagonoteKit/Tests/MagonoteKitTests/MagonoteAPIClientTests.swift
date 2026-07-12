import Foundation
import Testing
@testable import MagonoteKit

struct MagonoteAPIClientTests {
    @Test
    func authorizationHeaderIsInjected() async throws {
        let recorder = RequestRecorder()
        try await withStubbedClient(token: "abc123", handler: { request in
            recorder.record(request)
            return jsonResponse(url: request.url!, statusCode: 200, object: documentJSONObject())
        }) { client in
            _ = try await client.document(id: "doc-1")
        }

        #expect(recorder.request?.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test
    func unixMillisecondsDecodeToExpectedDate() async throws {
        let document = try await withStubbedClient(handler: { request in
            jsonResponse(url: request.url!, statusCode: 200, object: documentJSONObject())
        }) { client in
            try await client.document(id: "doc-1")
        }

        let expectedCapturedAt = Date(timeIntervalSince1970: Double(sampleCapturedAtMillis) / 1000)
        let expectedCreatedAt = Date(timeIntervalSince1970: Double(sampleCreatedAtMillis) / 1000)
        #expect(document.capturedAt == expectedCapturedAt)
        #expect(document.createdAt == expectedCreatedAt)
        #expect(document.archivedAt == nil)
        #expect(document.isArchived == false)
    }

    @Test
    func camelCaseKeysRoundTripThroughEncodeAndDecode() async throws {
        let newDocument = NewDocument(
            text: "hello",
            sourceAppName: "Xcode",
            sourceMachineName: "MacBook-Pro",
            capturedAt: Date(timeIntervalSince1970: Double(sampleCapturedAtMillis) / 1000)
        )

        let encoded = try JSONCoding.apiEncoder.encode(newDocument)
        let jsonObject = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(jsonObject["text"] as? String == "hello")
        #expect(jsonObject["sourceAppName"] as? String == "Xcode")
        #expect(jsonObject["sourceMachineName"] as? String == "MacBook-Pro")
        #expect(jsonObject["capturedAt"] as? Int64 == sampleCapturedAtMillis)

        let decoded = try JSONCoding.apiDecoder.decode(NewDocument.self, from: encoded)
        #expect(decoded == newDocument)
    }

    @Test
    func datesWithSubmillisecondPrecisionEncodeAsIntegerMilliseconds() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.1239)
        let newDocument = NewDocument(
            text: "hello",
            sourceAppName: "TextEdit",
            sourceMachineName: "MacBook-Pro",
            capturedAt: date
        )

        let encoded = try JSONCoding.apiEncoder.encode(newDocument)
        let jsonObject = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(jsonObject["capturedAt"] as? Int64 == 1_700_000_000_123)
    }

    @Test
    func notFoundEnvelopeMapsToNotFoundCase() async throws {
        do {
            _ = try await withStubbedClient(handler: { request in
                errorEnvelope(url: request.url!, statusCode: 404, code: "not_found", message: "document not found")
            }) { client in
                try await client.document(id: "missing")
            }
            Issue.record("Expected APIError.notFound to be thrown")
        } catch let error as APIError {
            guard case .notFound = error else {
                Issue.record("Expected .notFound, got \(error)")
                return
            }
        }
    }

    @Test
    func validationEnvelopeMapsToValidationCaseWithMessage() async throws {
        do {
            _ = try await withStubbedClient(handler: { request in
                errorEnvelope(url: request.url!, statusCode: 400, code: "validation_error", message: "text is required")
            }) { client in
                try await client.document(id: "doc-1")
            }
            Issue.record("Expected APIError.validation to be thrown")
        } catch let error as APIError {
            guard case .validation(let message) = error else {
                Issue.record("Expected .validation, got \(error)")
                return
            }
            #expect(message == "text is required")
        }
    }

    @Test
    func transportFailureMapsToNetworkCase() async throws {
        do {
            _ = try await withStubbedClient(handler: { _ in
                throw URLError(.notConnectedToInternet)
            }) { client in
                try await client.document(id: "doc-1")
            }
            Issue.record("Expected APIError.network to be thrown")
        } catch let error as APIError {
            guard case .network(let underlying) = error else {
                Issue.record("Expected .network, got \(error)")
                return
            }
            #expect((underlying as? URLError)?.code == .notConnectedToInternet)
        }
    }

    @Test
    func trailingSlashInBaseURLDoesNotDoubleSlashPath() async throws {
        let recorder = RequestRecorder()
        try await withStubbedClient(
            baseURL: URL(string: "https://api.magonote.example/")!,
            handler: { request in
                recorder.record(request)
                return jsonResponse(url: request.url!, statusCode: 200, object: documentJSONObject())
            }
        ) { client in
            _ = try await client.document(id: "doc-1")
        }

        #expect(recorder.request?.url?.path == "/api/reader/documents/doc-1")
        // baseURL のホストは "api.magonote.example" なので、単純に絶対文字列が "//api" を
        // 含むかどうかを見ると "https://api..." のスキーム区切り自体に一致してしまい、
        // 意図した「ホストの直後で path が二重スラッシュになっていないか」を検証できない。
        // そのためホスト直後の区切りを明示した "example//" が含まれないことを確認する。
        #expect(recorder.request?.url?.absoluteString.contains("example//") == false)
    }
}
