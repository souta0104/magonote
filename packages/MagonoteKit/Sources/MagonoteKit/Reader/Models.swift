import Foundation

/// A captured Document — the central Reader concept. See the ユビキタス言語
/// table in the design spec for term definitions.
public struct Document: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let sourceAppName: String
    public let sourceMachineName: String
    public let capturedAt: Date
    public let createdAt: Date
    public let archivedAt: Date?

    public init(
        id: String,
        text: String,
        sourceAppName: String,
        sourceMachineName: String,
        capturedAt: Date,
        createdAt: Date,
        archivedAt: Date?
    ) {
        self.id = id
        self.text = text
        self.sourceAppName = sourceAppName
        self.sourceMachineName = sourceMachineName
        self.capturedAt = capturedAt
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
}

/// A list-view projection of a Document: `text` is replaced by `preview`
/// (the first 300 characters, computed server-side).
public struct DocumentSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let preview: String
    public let sourceAppName: String
    public let sourceMachineName: String
    public let capturedAt: Date
    public let createdAt: Date
    public let archivedAt: Date?

    public init(
        id: String,
        preview: String,
        sourceAppName: String,
        sourceMachineName: String,
        capturedAt: Date,
        createdAt: Date,
        archivedAt: Date?
    ) {
        self.id = id
        self.preview = preview
        self.sourceAppName = sourceAppName
        self.sourceMachineName = sourceMachineName
        self.capturedAt = capturedAt
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
}

/// A flat comment on a Document (no threads, no replies).
public struct Comment: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let documentId: String
    public let body: String
    public let quote: String?
    public let createdAt: Date
    public let archivedAt: Date?

    public init(
        id: String,
        documentId: String,
        body: String,
        quote: String?,
        createdAt: Date,
        archivedAt: Date?
    ) {
        self.id = id
        self.documentId = documentId
        self.body = body
        self.quote = quote
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }
}

/// A single keyset-paginated page of ``DocumentSummary`` results.
public struct DocumentPage: Codable, Sendable, Equatable {
    public let documents: [DocumentSummary]
    public let nextCursor: String?

    public init(documents: [DocumentSummary], nextCursor: String?) {
        self.documents = documents
        self.nextCursor = nextCursor
    }
}

/// The payload sent to create a new Document via Capture.
public struct NewDocument: Codable, Sendable, Equatable {
    public let text: String
    public let sourceAppName: String
    public let sourceMachineName: String
    public let capturedAt: Date

    public init(text: String, sourceAppName: String, sourceMachineName: String, capturedAt: Date) {
        self.text = text
        self.sourceAppName = sourceAppName
        self.sourceMachineName = sourceMachineName
        self.capturedAt = capturedAt
    }
}

/// The Active / Archived state filter used when listing Documents.
public enum DocumentFilter: String, Sendable, Codable {
    case active
    case archived
}
