import MagonoteKit
import Observation

@MainActor
@Observable
final class DocumentDetailStore {
  private let client: any ReaderAPIClient
  private let documentID: String

  private(set) var document: Document?
  private(set) var comments: [Comment] = []
  private(set) var isLoading = false
  var showArchivedComments = false
  var error: APIError?

  init(documentID: String, client: any ReaderAPIClient) {
    self.documentID = documentID
    self.client = client
  }

  func load() async {
    guard !isLoading else {
      return
    }

    isLoading = true
    error = nil
    defer { isLoading = false }

    do {
      async let document = client.document(id: documentID)
      async let comments = client.comments(
        documentID: documentID,
        includeArchived: showArchivedComments
      )
      self.document = try await document
      self.comments = try await comments
    } catch {
      self.error = normalizedAPIError(error)
    }
  }

  func reloadComments() async {
    error = nil
    do {
      comments = try await client.comments(
        documentID: documentID,
        includeArchived: showArchivedComments
      )
    } catch {
      self.error = normalizedAPIError(error)
    }
  }

  func archive() async {
    do {
      document = try await client.archiveDocument(id: documentID)
    } catch {
      self.error = normalizedAPIError(error)
    }
  }

  func unarchive() async {
    do {
      document = try await client.unarchiveDocument(id: documentID)
    } catch {
      self.error = normalizedAPIError(error)
    }
  }

  func addComment(body: String, quote: String?) async -> Bool {
    do {
      let comment = try await client.createComment(
        documentID: documentID,
        body: body,
        quote: quote
      )
      comments.insert(comment, at: 0)
      return true
    } catch {
      self.error = normalizedAPIError(error)
      return false
    }
  }

  func archiveComment(id: String) async {
    await updateCommentArchiveState(id: id, archive: true)
  }

  func unarchiveComment(id: String) async {
    await updateCommentArchiveState(id: id, archive: false)
  }

  private func updateCommentArchiveState(id: String, archive: Bool) async {
    guard let index = comments.firstIndex(where: { $0.id == id }) else {
      return
    }

    let original = comments[index]
    if !showArchivedComments {
      comments.remove(at: index)
    }

    do {
      let updated: Comment
      if archive {
        updated = try await client.archiveComment(id: id)
      } else {
        updated = try await client.unarchiveComment(id: id)
      }

      if showArchivedComments {
        comments[index] = updated
      }
    } catch {
      if showArchivedComments {
        comments[index] = original
      } else {
        comments.insert(original, at: min(index, comments.count))
      }
      self.error = normalizedAPIError(error)
    }
  }
}
