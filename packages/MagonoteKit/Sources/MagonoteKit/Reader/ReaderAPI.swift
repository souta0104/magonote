import Foundation

/// Reader tool API calls. New tools should follow this pattern: an extension
/// on ``MagonoteAPIClient`` in `Tools/<name>/`.
extension MagonoteAPIClient {
    /// POST /api/reader/documents
    public func createDocument(_ new: NewDocument) async throws -> Document {
        try await post("/api/reader/documents", body: new)
    }

    /// GET /api/reader/documents?filter=&cursor=&limit=
    public func listDocuments(
        filter: DocumentFilter = .active,
        cursor: String? = nil,
        limit: Int = 30
    ) async throws -> DocumentPage {
        var query = [
            URLQueryItem(name: "filter", value: filter.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await get("/api/reader/documents", query: query)
    }

    /// GET /api/reader/documents/:id
    public func document(id: String) async throws -> Document {
        try await get("/api/reader/documents/\(id)")
    }

    /// POST /api/reader/documents/:id/archive
    public func archiveDocument(id: String) async throws -> Document {
        try await post("/api/reader/documents/\(id)/archive")
    }

    /// POST /api/reader/documents/:id/unarchive
    public func unarchiveDocument(id: String) async throws -> Document {
        try await post("/api/reader/documents/\(id)/unarchive")
    }

    /// GET /api/reader/documents/:id/comments?includeArchived=
    public func comments(documentID: String, includeArchived: Bool = false) async throws -> [Comment] {
        let query = [URLQueryItem(name: "includeArchived", value: String(includeArchived))]
        let response: CommentsResponse = try await get(
            "/api/reader/documents/\(documentID)/comments",
            query: query
        )
        return response.comments
    }

    /// POST /api/reader/documents/:id/comments
    public func createComment(documentID: String, body: String, quote: String?) async throws -> Comment {
        try await post(
            "/api/reader/documents/\(documentID)/comments",
            body: NewComment(body: body, quote: quote)
        )
    }

    /// POST /api/reader/comments/:id/archive
    public func archiveComment(id: String) async throws -> Comment {
        try await post("/api/reader/comments/\(id)/archive")
    }

    /// POST /api/reader/comments/:id/unarchive
    public func unarchiveComment(id: String) async throws -> Comment {
        try await post("/api/reader/comments/\(id)/unarchive")
    }
}

/// Request body for `POST /api/reader/documents/:id/comments`.
private struct NewComment: Encodable, Sendable {
    let body: String
    let quote: String?
}

/// Response body for `GET /api/reader/documents/:id/comments`.
private struct CommentsResponse: Decodable, Sendable {
    let comments: [Comment]
}
