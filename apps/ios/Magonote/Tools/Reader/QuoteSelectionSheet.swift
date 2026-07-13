import SwiftUI

struct QuoteSelectionSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var selection: TextSelection?
  @State private var selectedText = ""

  let text: String
  let onSelect: (String) -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        TextEditor(text: .constant(text), selection: $selection)
          .font(.body)
          .padding(.horizontal)
          .onChange(of: selection) { _, selection in
            selectedText = selectedSubstring(from: selection)
          }

        Divider()

        VStack(alignment: .leading, spacing: 12) {
          Text(selectedText.isEmpty ? "引用する範囲を選択してください" : selectedText)
            .font(.callout)
            .foregroundStyle(selectedText.isEmpty ? .secondary : .primary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)

          Button("引用に使う") {
            onSelect(selectedText)
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          .frame(maxWidth: .infinity)
          .disabled(selectedText.isEmpty)
        }
        .padding()
        .background(.bar)
      }
      .navigationTitle("引用を選択")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
      }
    }
  }

  private func selectedSubstring(from selection: TextSelection?) -> String {
    guard let indices = selection?.indices else {
      return ""
    }

    switch indices {
    case .selection(let range):
      return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    case .multiSelection(let ranges):
      return ranges.ranges
        .map { String(text[$0]) }
        .joined(separator: "\n…\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    @unknown default:
      return ""
    }
  }
}
