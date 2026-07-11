import MagonoteKit
import SwiftUI

struct DocumentListView: View {
  @Environment(SessionStore.self) private var session
  @State private var store: DocumentListStore
  private let client: any ReaderAPIClient

  init(client: any ReaderAPIClient) {
    self.client = client
    _store = State(initialValue: DocumentListStore(client: client))
  }

  var body: some View {
    List {
      if store.items.isEmpty, !store.isLoading {
        ContentUnavailableView(
          store.filter == .active ? "保存されたテキストはありません" : "アーカイブはありません",
          systemImage: store.filter == .active ? "text.page" : "archivebox"
        )
        .listRowBackground(Color.clear)
      }

      ForEach(store.items) { item in
        NavigationLink(value: item.id) {
          DocumentSummaryRow(item: item)
        }
        .swipeActions {
          Button(
            item.isArchived ? "アーカイブ解除" : "アーカイブ",
            systemImage: item.isArchived ? "archivebox.fill" : "archivebox"
          ) {
            Task {
              if item.isArchived {
                await store.unarchive(id: item.id)
              } else {
                await store.archive(id: item.id)
              }
            }
          }
          .tint(item.isArchived ? .blue : .orange)
        }
        .onAppear {
          if item.id == store.items.last?.id {
            Task { await store.loadMore() }
          }
        }
      }

      if store.isLoading, !store.items.isEmpty {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
      }
    }
    .navigationTitle("Reader")
    .navigationDestination(for: String.self) { documentID in
      DocumentDetailView(documentID: documentID, client: client)
    }
    .refreshable {
      await store.refresh()
    }
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Menu {
          Picker(
            "表示",
            selection: Binding(
              get: { store.filter },
              set: { filter in Task { await store.setFilter(filter) } }
            )
          ) {
            Text("未アーカイブ").tag(DocumentFilter.active)
            Text("アーカイブ済み").tag(DocumentFilter.archived)
          }
        } label: {
          Label(
            store.filter == .active ? "未アーカイブ" : "アーカイブ済み",
            systemImage: "line.3.horizontal.decrease.circle"
          )
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          if let email = session.emailAddress {
            Text(email)
          }
          Button("ログアウト", role: .destructive) {
            try? session.signOut()
          }
        } label: {
          Image(systemName: "person.crop.circle")
        }
      }
    }
    .overlay {
      if store.isLoading, store.items.isEmpty {
        ProgressView()
      }
    }
    .task {
      if store.items.isEmpty {
        await store.refresh()
      }
    }
    .apiErrorAlert(error: $store.error)
  }
}

private struct DocumentSummaryRow: View {
  let item: DocumentSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(item.sourceAppName, systemImage: "macwindow")
        Spacer()
        Text(item.capturedAt, format: .relative(presentation: .named))
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      Text(item.preview)
        .font(.body)
        .lineLimit(3)

      Text(item.sourceMachineName)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 4)
  }
}

extension View {
  func apiErrorAlert(error: Binding<APIError?>) -> some View {
    alert(
      "処理できませんでした",
      isPresented: Binding(
        get: { error.wrappedValue != nil },
        set: { if !$0 { error.wrappedValue = nil } }
      )
    ) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(error.wrappedValue?.userMessage ?? "不明なエラーです")
    }
  }
}
