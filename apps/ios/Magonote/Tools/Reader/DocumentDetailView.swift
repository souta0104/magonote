import MarkdownUI
import SwiftUI

struct DocumentDetailView: View {
  @State private var store: DocumentDetailStore
  @State private var isComposerPresented = false

  init(documentID: String, client: any ReaderAPIClient) {
    _store = State(
      initialValue: DocumentDetailStore(documentID: documentID, client: client)
    )
  }

  var body: some View {
    List {
      if let document = store.document {
        Section {
          VStack(alignment: .leading, spacing: 6) {
            Label(document.sourceAppName, systemImage: "macwindow")
            Label(document.sourceMachineName, systemImage: "desktopcomputer")
            Label {
              Text(document.capturedAt, format: .dateTime)
            } icon: {
              Image(systemName: "clock")
            }
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }

        Section("本文") {
          Markdown(document.text)
            .magonoteMarkdownStyle()
            .textSelection(.enabled)
            .padding(.vertical, 6)
        }

        CommentsSection(store: store)
      } else if !store.isLoading {
        ContentUnavailableView("ドキュメントを表示できません", systemImage: "exclamationmark.triangle")
      }
    }
    .navigationTitle("ドキュメント")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if let document = store.document {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            isComposerPresented = true
          } label: {
            Label("コメント", systemImage: "bubble.left.and.bubble.right")
          }

          Button {
            Task {
              if document.isArchived {
                await store.unarchive()
              } else {
                await store.archive()
              }
            }
          } label: {
            Label(
              document.isArchived ? "アーカイブ解除" : "アーカイブ",
              systemImage: document.isArchived ? "archivebox.fill" : "archivebox"
            )
          }
        }
      }
    }
    .overlay {
      if store.isLoading {
        ProgressView()
      }
    }
    .task {
      if store.document == nil {
        await store.load()
      }
    }
    .sheet(isPresented: $isComposerPresented) {
      if let document = store.document {
        CommentComposerSheet(documentText: document.text) { body, quote in
          await store.addComment(body: body, quote: quote)
        }
      }
    }
    .apiErrorAlert(error: $store.error)
  }
}
