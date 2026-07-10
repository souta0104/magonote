import Foundation
import Testing
@testable import MagonoteKit

struct ReaderAPITests {
    @Test
    func createDocumentSendsExpectedRequestBody() async throws {
        let recorder = RequestRecorder()
        try await withStubbedClient(handler: { request in
            recorder.record(request)
            return jsonResponse(url: request.url!, statusCode: 201, object: documentJSONObject())
        }) { client in
            let capturedAt = Date(timeIntervalSince1970: Double(sampleCapturedAtMillis) / 1000)
            let newDocument = NewDocument(
                text: "captured text",
                sourceAppName: "Xcode",
                sourceMachineName: "MacBook-Pro",
                capturedAt: capturedAt
            )

            _ = try await client.createDocument(newDocument)
        }

        let request = try #require(recorder.request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/reader/documents")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBodyOrStream())
        let jsonObject = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(jsonObject["text"] as? String == "captured text")
        #expect(jsonObject["sourceAppName"] as? String == "Xcode")
        #expect(jsonObject["sourceMachineName"] as? String == "MacBook-Pro")
        #expect(jsonObject["capturedAt"] as? Int64 == sampleCapturedAtMillis)
        #expect(jsonObject.count == 4)
    }

    @Test
    func listDocumentsDecodesPageEnvelope() async throws {
        let page = try await withStubbedClient(handler: { request in
            jsonResponse(
                url: request.url!,
                statusCode: 200,
                object: [
                    "documents": [
                        [
                            "id": "doc-1",
                            "preview": "hello world",
                            "sourceAppName": "Xcode",
                            "sourceMachineName": "MacBook-Pro",
                            "capturedAt": sampleCapturedAtMillis,
                            "createdAt": sampleCreatedAtMillis,
                            "archivedAt": NSNull(),
                        ] as [String: Any],
                    ],
                    "nextCursor": "next-cursor-token",
                ]
            )
        }) { client in
            try await client.listDocuments(filter: .active, cursor: nil, limit: 30)
        }

        #expect(page.documents.count == 1)
        #expect(page.documents.first?.id == "doc-1")
        #expect(page.documents.first?.preview == "hello world")
        #expect(page.nextCursor == "next-cursor-token")
    }

    @Test
    func commentsDecodesFlatCommentArrayFromEnvelope() async throws {
        let comments = try await withStubbedClient(handler: { request in
            jsonResponse(
                url: request.url!,
                statusCode: 200,
                object: [
                    "comments": [
                        [
                            "id": "comment-1",
                            "documentId": "doc-1",
                            "body": "nice",
                            "quote": "quoted text",
                            "createdAt": sampleCreatedAtMillis,
                            "archivedAt": NSNull(),
                        ] as [String: Any],
                    ]
                ]
            )
        }) { client in
            try await client.comments(documentID: "doc-1", includeArchived: true)
        }

        #expect(comments.count == 1)
        #expect(comments.first?.id == "comment-1")
        #expect(comments.first?.documentId == "doc-1")
        #expect(comments.first?.quote == "quoted text")
        #expect(comments.first?.isArchived == false)
    }

    @Test
    func archiveDocumentIsAnIdempotentPostWithNoBody() async throws {
        let recorder = RequestRecorder()
        let document = try await withStubbedClient(handler: { request in
            recorder.record(request)
            return jsonResponse(
                url: request.url!,
                statusCode: 200,
                object: documentJSONObject(archivedAt: sampleCreatedAtMillis)
            )
        }) { client in
            try await client.archiveDocument(id: "doc-1")
        }

        #expect(recorder.request?.httpMethod == "POST")
        #expect(recorder.request?.url?.path == "/api/reader/documents/doc-1/archive")
        #expect(recorder.request?.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(document.isArchived == true)
    }
}

private extension URLRequest {
    /// `httpBody` is nil on requests replayed through `URLProtocol`; the body
    /// is exposed via `httpBodyStream` instead. This reads it back to `Data`.
    func httpBodyOrStream() -> Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
