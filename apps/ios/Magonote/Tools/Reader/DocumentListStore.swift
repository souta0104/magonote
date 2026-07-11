import Foundation
import MagonoteKit
import Observation

@MainActor
@Observable
final class DocumentListStore {
  private let client: any ReaderAPIClient
  private var listRequestID: UUID?
  private var pendingDocumentIDs: Set<String> = []

  private(set) var items: [DocumentSummary] = []
  private(set) var nextCursor: String?
  private(set) var isLoading = false
  var filter: DocumentFilter = .active
  var error: APIError?

  init(client: any ReaderAPIClient) {
    self.client = client
  }

  func refresh() async {
    let requestID = UUID()
    let requestedFilter = filter
    listRequestID = requestID
    isLoading = true
    error = nil
    defer {
      if listRequestID == requestID {
        listRequestID = nil
        isLoading = false
      }
    }

    do {
      let page = try await client.listDocuments(filter: requestedFilter, cursor: nil, limit: 30)
      guard listRequestID == requestID, filter == requestedFilter else {
        return
      }
      items = page.documents.filter { !pendingDocumentIDs.contains($0.id) }
      nextCursor = page.nextCursor
    } catch {
      if listRequestID == requestID {
        self.error = normalizedAPIError(error)
      }
    }
  }

  func loadMore() async {
    guard !isLoading, let nextCursor else {
      return
    }

    let requestID = UUID()
    let requestedFilter = filter
    let requestedCursor = nextCursor
    listRequestID = requestID
    isLoading = true
    error = nil
    defer {
      if listRequestID == requestID {
        listRequestID = nil
        isLoading = false
      }
    }

    do {
      let page = try await client.listDocuments(
        filter: requestedFilter,
        cursor: requestedCursor,
        limit: 30
      )
      guard listRequestID == requestID, filter == requestedFilter else {
        return
      }
      let existingIDs = Set(items.map(\.id))
      items.append(
        contentsOf: page.documents.filter {
          !existingIDs.contains($0.id) && !pendingDocumentIDs.contains($0.id)
        }
      )
      self.nextCursor = page.nextCursor
    } catch {
      if listRequestID == requestID {
        self.error = normalizedAPIError(error)
      }
    }
  }

  func setFilter(_ filter: DocumentFilter) async {
    guard self.filter != filter else {
      return
    }

    self.filter = filter
    items = []
    nextCursor = nil
    listRequestID = nil
    isLoading = false
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

    items.remove(at: index)
    listRequestID = nil
    isLoading = false
    pendingDocumentIDs.insert(id)
    error = nil

    do {
      if archive {
        _ = try await client.archiveDocument(id: id)
      } else {
        _ = try await client.unarchiveDocument(id: id)
      }
      pendingDocumentIDs.remove(id)
      await refresh()
    } catch {
      pendingDocumentIDs.remove(id)
      await refresh()
      self.error = normalizedAPIError(error)
    }
  }
}
