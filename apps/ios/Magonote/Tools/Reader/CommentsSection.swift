import SwiftUI

struct CommentsSection: View {
  @Bindable var store: DocumentDetailStore

  var body: some View {
    Section {
      Toggle(
        "アーカイブ済みを表示",
        isOn: Binding(
          get: { store.showArchivedComments },
          set: { value in
            store.showArchivedComments = value
            Task { await store.reloadComments() }
          }
        ))

      if store.comments.isEmpty {
        Text("コメントはありません")
          .foregroundStyle(.secondary)
      }

      ForEach(store.comments) { comment in
        VStack(alignment: .leading, spacing: 8) {
          if let quote = comment.quote {
            Text(quote)
              .font(.callout)
              .foregroundStyle(.secondary)
              .padding(.leading, 10)
              .overlay(alignment: .leading) {
                Rectangle()
                  .fill(.secondary)
                  .frame(width: 3)
              }
          }

          Text(comment.body)

          Text(comment.createdAt, format: .relative(presentation: .named))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .swipeActions {
          Button(
            comment.isArchived ? "アーカイブ解除" : "アーカイブ",
            systemImage: comment.isArchived ? "archivebox.fill" : "archivebox"
          ) {
            Task {
              if comment.isArchived {
                await store.unarchiveComment(id: comment.id)
              } else {
                await store.archiveComment(id: comment.id)
              }
            }
          }
          .tint(comment.isArchived ? .blue : .orange)
        }
        .contextMenu {
          Button(comment.isArchived ? "アーカイブ解除" : "アーカイブ") {
            Task {
              if comment.isArchived {
                await store.unarchiveComment(id: comment.id)
              } else {
                await store.archiveComment(id: comment.id)
              }
            }
          }
        }
      }
    } header: {
      Text("コメント")
    }
  }
}
