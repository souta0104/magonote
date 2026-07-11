import SwiftUI

struct CommentComposerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var bodyText = ""
  @State private var quote: String?
  @State private var isSelectingQuote = false
  @State private var isSubmitting = false

  let documentText: String
  let submit: (String, String?) async -> Bool

  var body: some View {
    NavigationStack {
      Form {
        Section("コメント") {
          TextEditor(text: $bodyText)
            .frame(minHeight: 140)
        }

        Section("引用") {
          if let quote {
            Text(quote)
              .font(.callout)
              .foregroundStyle(.secondary)

            Button("引用を削除", role: .destructive) {
              self.quote = nil
            }
          }

          Button(quote == nil ? "引用を選択…" : "引用を選び直す…") {
            isSelectingQuote = true
          }
        }
      }
      .navigationTitle("コメントを追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") {
            Task { await save() }
          }
          .disabled(trimmedBody.isEmpty || isSubmitting)
        }
      }
      .sheet(isPresented: $isSelectingQuote) {
        QuoteSelectionSheet(text: documentText) { quote in
          self.quote = quote
        }
      }
    }
  }

  private var trimmedBody: String {
    bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func save() async {
    isSubmitting = true
    defer { isSubmitting = false }

    if await submit(trimmedBody, quote) {
      dismiss()
    }
  }
}
