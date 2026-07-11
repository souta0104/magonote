import MarkdownUI
import SwiftUI

extension View {
  func magonoteMarkdownStyle() -> some View {
    markdownTheme(.gitHub)
      .markdownBlockStyle(\.codeBlock) { configuration in
        ScrollView(.horizontal) {
          configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .markdownBlockStyle(\.blockquote) { configuration in
        configuration.label
          .padding(.leading, 14)
          .overlay(alignment: .leading) {
            Rectangle()
              .fill(Color(uiColor: .separator))
              .frame(width: 4)
          }
      }
  }
}
