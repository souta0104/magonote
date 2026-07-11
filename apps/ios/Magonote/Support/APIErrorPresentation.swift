import Foundation
import MagonoteKit

extension APIError {
  var userMessage: String {
    switch self {
    case .unauthorized:
      "ログインの有効期限が切れました。もう一度ログインしてください。"
    case .forbidden:
      "このアカウントでは Magonote を利用できません。"
    case .notFound:
      "対象のデータが見つかりませんでした。"
    case .validation(let message):
      message
    case .server(_, let message):
      "サーバーでエラーが発生しました: \(message)"
    case .network:
      "通信できませんでした。ネットワーク接続を確認してください。"
    case .decoding:
      "サーバーから受け取ったデータを読み取れませんでした。"
    }
  }
}

func normalizedAPIError(_ error: any Error) -> APIError {
  error as? APIError ?? .network(error)
}
