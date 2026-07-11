import MagonoteKit
import Observation

@MainActor
@Observable
final class DocumentListStore {
  private let client: any ReaderAPIClient

  private(set) var items: [DocumentSummary] = []
  private(set) var nextCursor: String?
  private(set) var isLoading = false
  var filter: DocumentFilter = .active
  var error: APIError?

  init(client: any ReaderAPIClient) {
    self.client = client
  }

  func refresh() async {
    guard !isLoading else {
      return
    }

    isLoading = true
    error = nil
    defer { isLoading = false }

    do {
      let page = try await client.listDocuments(filter: filter, cursor: nil, limit: 30)
      items = page.documents
      nextCursor = page.nextCursor
    } catch {
      self.error = normalizedAPIError(error)
    }
  }

  func loadMore() async {
    guard !isLoading, let nextCursor else {
      return
    }

    isLoading = true
    error = nil
    defer { isLoading = false }

    do {
      let page = try await client.listDocuments(
        filter: filter,
        cursor: nextCursor,
        limit: 30
      )
      let existingIDs = Set(items.map(\.id))
      items.append(contentsOf: page.documents.filter { !existingIDs.contains($0.id) })
      self.nextCursor = page.nextCursor
    } catch {
      self.error = normalizedAPIError(error)
    }
  }

  func setFilter(_ filter: DocumentFilter) async {
    guard self.filter != filter else {
      return
    }

    self.filter = filter
    items = []
    nextCursor = nil
    await refresh()
  }

  func archive(id: String) async {
    await updateArchiveState(id: id, archive: true)
  }

  func unarchive(id: String) async {
    await updateArchiveState(id: id, archive: false)
  }

  private func updateArchiveState(id: String, archive: Bool) async {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      return
    }

    let removed = items.remove(at: index)
    error = nil

    do {
      if archive {
        _ = try await client.archiveDocument(id: id)
      } else {
        _ = try await client.unarchiveDocument(id: id)
      }
    } catch {
      items.insert(removed, at: min(index, items.count))
      self.error = normalizedAPIError(error)
    }
  }
}
