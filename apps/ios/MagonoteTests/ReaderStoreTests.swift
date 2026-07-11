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
    client.pages = [
      DocumentPage(documents: [summary(id: "1")], nextCursor: nil),
      DocumentPage(documents: [summary(id: "1")], nextCursor: nil),
    ]
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
    XCTAssertEqual(store.comments.map(\.id), ["comment-1", "comment-2"])
    XCTAssertTrue(didAdd)
    XCTAssertEqual(client.createCommentRequests.first?.body, "new")
    XCTAssertEqual(client.createCommentRequests.first?.quote, "quote")
  }

  func testOldFilterResponseDoesNotReplaceLatestFilter() async {
    let client = FakeReaderAPIClient()
    client.suspendListRequests = true
    let store = DocumentListStore(client: client)

    let activeRequest = Task { await store.refresh() }
    await waitUntil { client.listContinuations.count == 1 }
    let archivedRequest = Task { await store.setFilter(.archived) }
    await waitUntil { client.listContinuations.count == 2 }

    client.resumeListRequest(
      at: 1,
      with: DocumentPage(documents: [summary(id: "archived", archived: true)], nextCursor: nil)
    )
    await archivedRequest.value
    client.resumeListRequest(
      at: 0,
      with: DocumentPage(documents: [summary(id: "active")], nextCursor: nil)
    )
    await activeRequest.value

    XCTAssertEqual(store.filter, .archived)
    XCTAssertEqual(store.items.map(\.id), ["archived"])
  }

  func testRefreshDoesNotRestoreDocumentWhileArchiveIsPending() async {
    let client = FakeReaderAPIClient()
    client.pages = [
      DocumentPage(documents: [summary(id: "1")], nextCursor: nil),
      DocumentPage(documents: [summary(id: "1")], nextCursor: nil),
      DocumentPage(documents: [], nextCursor: nil),
    ]
    client.detail = document(id: "1")
    client.suspendArchiveDocument = true
    let store = DocumentListStore(client: client)
    await store.refresh()

    let archiveRequest = Task { await store.archive(id: "1") }
    await waitUntil { client.archiveDocumentContinuation != nil }
    await store.refresh()

    XCTAssertTrue(store.items.isEmpty)
    client.resumeArchiveDocument(with: document(id: "1"))
    await archiveRequest.value
    XCTAssertTrue(store.items.isEmpty)
  }

  func testLoadMoreStartedBeforeArchiveCannotRestoreDocument() async {
    let client = FakeReaderAPIClient()
    client.pages = [
      DocumentPage(documents: [summary(id: "1")], nextCursor: "next"),
    ]
    client.detail = document(id: "1")
    let store = DocumentListStore(client: client)
    await store.refresh()

    client.suspendListRequests = true
    let loadMoreRequest = Task { await store.loadMore() }
    await waitUntil { client.listContinuations.count == 1 }
    let archiveRequest = Task { await store.archive(id: "1") }
    await waitUntil { client.listContinuations.count == 2 }

    client.resumeListRequest(
      at: 0,
      with: DocumentPage(documents: [summary(id: "1")], nextCursor: nil)
    )
    await loadMoreRequest.value
    client.resumeListRequest(at: 1, with: DocumentPage(documents: [], nextCursor: nil))
    await archiveRequest.value

    XCTAssertTrue(store.items.isEmpty)
  }

  func testArchiveRefreshesDestinationFilterAfterRequestCompletes() async {
    let client = FakeReaderAPIClient()
    client.pages = [
      DocumentPage(documents: [summary(id: "1")], nextCursor: nil),
      DocumentPage(documents: [], nextCursor: nil),
      DocumentPage(documents: [summary(id: "1", archived: true)], nextCursor: nil),
    ]
    client.detail = document(id: "1")
    client.suspendArchiveDocument = true
    let store = DocumentListStore(client: client)
    await store.refresh()

    let archiveRequest = Task { await store.archive(id: "1") }
    await waitUntil { client.archiveDocumentContinuation != nil }
    await store.setFilter(.archived)
    XCTAssertTrue(store.items.isEmpty)

    client.resumeArchiveDocument(with: document(id: "1"))
    await archiveRequest.value

    XCTAssertEqual(store.filter, .archived)
    XCTAssertEqual(store.items.map(\.id), ["1"])
  }

  func testOldCommentsResponseDoesNotReplaceLatestArchivedState() async {
    let client = FakeReaderAPIClient()
    client.suspendCommentRequests = true
    let store = DocumentDetailStore(documentID: "1", client: client)

    let activeRequest = Task { await store.reloadComments() }
    await waitUntil { client.commentContinuations.count == 1 }
    store.showArchivedComments = true
    let archivedRequest = Task { await store.reloadComments() }
    await waitUntil { client.commentContinuations.count == 2 }

    client.resumeCommentRequest(at: 1, with: [comment(id: "archived")])
    await archivedRequest.value
    client.resumeCommentRequest(at: 0, with: [comment(id: "active")])
    await activeRequest.value

    XCTAssertTrue(store.showArchivedComments)
    XCTAssertEqual(store.comments.map(\.id), ["archived"])
  }

  func testArchiveCommentFindsCurrentIndexAfterReload() async {
    let client = FakeReaderAPIClient()
    client.commentItems = [comment(id: "1"), comment(id: "2")]
    client.suspendArchiveComment = true
    let store = DocumentDetailStore(documentID: "1", client: client)
    store.showArchivedComments = true
    await store.reloadComments()

    let archiveRequest = Task { await store.archiveComment(id: "2") }
    await waitUntil { client.archiveCommentContinuation != nil }
    client.commentItems = [comment(id: "1"), comment(id: "2", archived: true)]
    await store.reloadComments()
    client.resumeArchiveComment(with: comment(id: "2", archived: true))
    await archiveRequest.value

    XCTAssertEqual(store.comments.map(\.id), ["1", "2"])
  }

  func testArchiveCommentReloadsCurrentFilterAfterToggle() async {
    let client = FakeReaderAPIClient()
    client.commentItems = [comment(id: "1")]
    client.suspendArchiveComment = true
    let store = DocumentDetailStore(documentID: "1", client: client)
    await store.reloadComments()

    let archiveRequest = Task { await store.archiveComment(id: "1") }
    await waitUntil { client.archiveCommentContinuation != nil }

    store.showArchivedComments = true
    client.suspendCommentRequests = true
    let staleReload = Task { await store.reloadComments() }
    await waitUntil { client.commentContinuations.count == 1 }
    client.resumeCommentRequest(at: 0, with: [comment(id: "1")])
    await staleReload.value

    client.resumeArchiveComment(with: comment(id: "1", archived: true))
    await waitUntil { client.commentContinuations.count == 2 }
    client.resumeCommentRequest(
      at: 1,
      with: [comment(id: "1", archived: true)]
    )
    await archiveRequest.value

    XCTAssertTrue(store.showArchivedComments)
    XCTAssertNotNil(store.comments.first?.archivedAt)
  }

  func testArchiveCommentKeepsMutationResultWhenReloadFails() async {
    let client = FakeReaderAPIClient()
    client.commentItems = [comment(id: "1")]
    client.suspendArchiveComment = true
    let store = DocumentDetailStore(documentID: "1", client: client)
    await store.reloadComments()

    let archiveRequest = Task { await store.archiveComment(id: "1") }
    await waitUntil { client.archiveCommentContinuation != nil }
    store.showArchivedComments = true
    client.commentError = APIError.server(status: 500, message: "reload failed")
    client.resumeArchiveComment(with: comment(id: "1", archived: true))
    await archiveRequest.value

    XCTAssertEqual(store.comments.map(\.id), ["1"])
    XCTAssertNotNil(store.comments.first?.archivedAt)
  }

  func testArchiveCommentRestoresOriginalWhenMutationAndReloadFail() async {
    let client = FakeReaderAPIClient()
    client.commentItems = [comment(id: "1")]
    let store = DocumentDetailStore(documentID: "1", client: client)
    await store.reloadComments()

    client.commentItems = []
    client.commentError = APIError.server(status: 500, message: "reload failed")
    await store.archiveComment(id: "1")

    XCTAssertEqual(store.comments.map(\.id), ["1"])
    XCTAssertNil(store.comments.first?.archivedAt)
    guard case .notFound = store.error else {
      return XCTFail("Expected the archive error to be preserved")
    }
  }

  private func waitUntil(
    _ condition: @escaping @MainActor () -> Bool
  ) async {
    while !condition() {
      await Task.yield()
    }
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

  private func comment(id: String, archived: Bool = false) -> Comment {
    Comment(
      id: id,
      documentId: "1",
      body: "body",
      quote: nil,
      createdAt: .init(timeIntervalSince1970: 1_000),
      archivedAt: archived ? .init(timeIntervalSince1970: 2_000) : nil
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
  var commentError: (any Error)?
  var createdComment: Comment?
  var archiveError: (any Error)?
  var createCommentRequests: [CreateCommentRequest] = []
  var suspendListRequests = false
  var listContinuations: [CheckedContinuation<DocumentPage, any Error>?] = []
  var suspendCommentRequests = false
  var commentContinuations: [CheckedContinuation<[Comment], any Error>?] = []
  var suspendArchiveDocument = false
  var archiveDocumentContinuation: CheckedContinuation<Document, any Error>?
  var suspendArchiveComment = false
  var archiveCommentContinuation: CheckedContinuation<Comment, any Error>?

  func listDocuments(
    filter: DocumentFilter,
    cursor: String?,
    limit: Int
  ) async throws -> DocumentPage {
    listRequests.append(.init(filter: filter, cursor: cursor, limit: limit))
    if suspendListRequests {
      return try await withCheckedThrowingContinuation { continuation in
        listContinuations.append(continuation)
      }
    }
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
    if suspendArchiveDocument {
      return try await withCheckedThrowingContinuation { continuation in
        archiveDocumentContinuation = continuation
      }
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
    if let commentError {
      throw commentError
    }
    if suspendCommentRequests {
      return try await withCheckedThrowingContinuation { continuation in
        commentContinuations.append(continuation)
      }
    }
    return commentItems
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
    if suspendArchiveComment {
      return try await withCheckedThrowingContinuation { continuation in
        archiveCommentContinuation = continuation
      }
    }
    return comment
  }

  func unarchiveComment(id: String) async throws -> Comment {
    guard let comment = commentItems.first(where: { $0.id == id }) else {
      throw APIError.notFound
    }
    return comment
  }

  func resumeListRequest(at index: Int, with page: DocumentPage) {
    let continuation = listContinuations[index]
    listContinuations[index] = nil
    continuation?.resume(returning: page)
  }

  func resumeCommentRequest(at index: Int, with comments: [Comment]) {
    let continuation = commentContinuations[index]
    commentContinuations[index] = nil
    continuation?.resume(returning: comments)
  }

  func resumeArchiveDocument(with document: Document) {
    let continuation = archiveDocumentContinuation
    archiveDocumentContinuation = nil
    continuation?.resume(returning: document)
  }

  func resumeArchiveComment(with comment: Comment) {
    let continuation = archiveCommentContinuation
    archiveCommentContinuation = nil
    continuation?.resume(returning: comment)
  }
}
