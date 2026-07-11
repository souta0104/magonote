import Foundation
import MagonoteKit

enum APIClientFactory {
  static let serverBaseURLKey = "MagonoteServerBaseURL"
  static let productionBaseURL = URL(
    string: "https://magonote-api.knock-02b.workers.dev"
  )!

  static func configuredBaseURL(bundle: Bundle = .main) -> URL {
    guard
      let value = bundle.object(forInfoDictionaryKey: serverBaseURLKey) as? String,
      let url = URL(string: value),
      isAllowedServerURL(url)
    else {
      return productionBaseURL
    }

    return url
  }

  static func makeClient() -> MagonoteAPIClient {
    MagonoteAPIClient(
      baseURL: configuredBaseURL(),
      tokenProvider: FirebaseAuthTokenProvider()
    )
  }

  private static func isAllowedServerURL(_ url: URL) -> Bool {
    if url.scheme == "https" {
      return true
    }

    guard url.scheme == "http", let host = url.host?.lowercased() else {
      return false
    }

    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }
}
