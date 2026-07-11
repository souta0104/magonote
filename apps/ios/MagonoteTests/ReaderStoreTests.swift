import MagonoteKit
import XCTest

@testable import Magonote

@MainActor
final class ReaderStoreTests: XCTestCase {
  func testRefreshAndLoadMoreReplaceThenAppendUniqueDocuments() async {
    let client = FakeReaderAPIClient()
    client.pages = [
      DocumentPage(documents: [summary(id: "1")], nextCursor: "next"),
      DocumentPage(documents: [summary(id: "1"), summary(id: "2")], nextCursor: nil),
    ]
    let store = DocumentListStore(client: client)

    await store.refresh()
    await store.loadMore()

    XCTAssertEqual(store.items.map(\.id), ["1", "2"])
    XCTAssertNil(store.nextCursor)
    XCTAssertEqual(client.listRequests.map(\.cursor), [nil, "next"])
  }

  func testChangingFilterClearsItemsAndRequestsFirstPage() async {
    let client = FakeReaderAPIClient()
    client.pages = [
      DocumentPage(documents: [summary(id: "1")], nextCursor: nil),
      DocumentPage(documents: [summary(id: "2", archived: true)], nextCursor: nil),
    ]
    let store = DocumentListStore(client: client)

    await store.refresh()
    await store.setFilter(.archived)

    XCTAssertEqual(store.filter, .archived)
    XCTAssertEqual(store.items.map(\.id), ["2"])
    XCTAssertEqual(client.listRequests.map(\.filter), [.active, .archived])
  }

  func testArchiveRollsBackOptimisticRemovalWhenRequestFails() async {
    let client = FakeReaderAPIClient()
    client.pages = [DocumentPage(documents: [summary(id: "1")], nextCursor: nil)]
    client.archiveError = APIError.server(status: 500, message: "failed")
    let store = DocumentListStore(client: client)

    await store.refresh()
    await store.archive(id: "1")

    XCTAssertEqual(store.items.map(\.id), ["1"])
    XCTAssertNotNil(store.error)
  }

  func testDetailLoadsDocumentAndCommentsThenAddsComment() async {
    let client = FakeReaderAPIClient()
    client.detail = document(id: "1")
    client.commentItems = [comment(id: "comment-1")]
    client.createdComment = comment(id: "comment-2")
    let store = DocumentDetailStore(documentID: "1", client: client)

    await store.load()
    let didAdd = await store.addComment(body: "new", quote: "quote")

    XCTAssertEqual(store.document?.id, "1")
    XCTAssertEqual(store.comments.map(\.id), ["comment-2", "comment-1"])
    XCTAssertTrue(didAdd)
    XCTAssertEqual(client.createCommentRequests.first?.body, "new")
    XCTAssertEqual(client.createCommentRequests.first?.quote, "quote")
  }

  private func summary(id: String, archived: Bool = false) -> DocumentSummary {
    DocumentSummary(
      id: id,
      preview: "preview-\(id)",
      sourceAppName: "Codex",
      sourceMachineName: "Mac",
      capturedAt: .init(timeIntervalSince1970: 1_000),
      createdAt: .init(timeIntervalSince1970: 1_000),
      archivedAt: archived ? .init(timeIntervalSince1970: 2_000) : nil
    )
  }

  private func document(id: String) -> Document {
    Document(
      id: id,
      text: "# Document",
      sourceAppName: "Codex",
      sourceMachineName: "Mac",
      capturedAt: .init(timeIntervalSince1970: 1_000),
      createdAt: .init(timeIntervalSince1970: 1_000),
      archivedAt: nil
    )
  }

  private func comment(id: String) -> Comment {
    Comment(
      id: id,
      documentId: "1",
      body: "body",
      quote: nil,
      createdAt: .init(timeIntervalSince1970: 1_000),
      archivedAt: nil
    )
  }
}

@MainActor
private final class FakeReaderAPIClient: ReaderAPIClient, @unchecked Sendable {
  struct ListRequest {
    let filter: DocumentFilter
    let cursor: String?
    let limit: Int
  }

  struct CreateCommentRequest {
    let documentID: String
    let body: String
    let quote: String?
  }

  var pages: [DocumentPage] = []
  var listRequests: [ListRequest] = []
  var detail: Document?
  var commentItems: [Comment] = []
  var createdComment: Comment?
  var archiveError: (any Error)?
  var createCommentRequests: [CreateCommentRequest] = []

  func listDocuments(
    filter: DocumentFilter,
    cursor: String?,
    limit: Int
  ) async throws -> DocumentPage {
    listRequests.append(.init(filter: filter, cursor: cursor, limit: limit))
    return pages.removeFirst()
  }

  func document(id: String) async throws -> Document {
    guard let detail else {
      throw APIError.notFound
    }
    return detail
  }

  func archiveDocument(id: String) async throws -> Document {
    if let archiveError {
      throw archiveError
    }
    guard let detail else {
      throw APIError.notFound
    }
    return detail
  }

  func unarchiveDocument(id: String) async throws -> Document {
    guard let detail else {
      throw APIError.notFound
    }
    return detail
  }

  func comments(documentID: String, includeArchived: Bool) async throws -> [Comment] {
    commentItems
  }

  func createComment(documentID: String, body: String, quote: String?) async throws -> Comment {
    createCommentRequests.append(.init(documentID: documentID, body: body, quote: quote))
    guard let createdComment else {
      throw APIError.notFound
    }
    return createdComment
  }

  func archiveComment(id: String) async throws -> Comment {
    guard let comment = commentItems.first(where: { $0.id == id }) else {
      throw APIError.notFound
    }
    return comment
  }

  func unarchiveComment(id: String) async throws -> Comment {
    guard let comment = commentItems.first(where: { $0.id == id }) else {
      throw APIError.notFound
    }
    return comment
  }
}
