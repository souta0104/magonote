import MagonoteKit

@MainActor
protocol ReaderAPIClient: Sendable {
  func listDocuments(
    filter: DocumentFilter,
    cursor: String?,
    limit: Int
  ) async throws -> DocumentPage
  func document(id: String) async throws -> Document
  func archiveDocument(id: String) async throws -> Document
  func unarchiveDocument(id: String) async throws -> Document
  func comments(documentID: String, includeArchived: Bool) async throws -> [Comment]
  func createComment(documentID: String, body: String, quote: String?) async throws -> Comment
  func archiveComment(id: String) async throws -> Comment
  func unarchiveComment(id: String) async throws -> Comment
}

extension MagonoteAPIClient: ReaderAPIClient {}
