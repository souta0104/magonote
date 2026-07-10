import Foundation
import MagonoteKit

enum APIClientFactory {
    static let serverBaseURLKey = "serverBaseURL"
    static let productionBaseURL = URL(
        string: "https://magonote-api.knock-02b.workers.dev"
    )!

    static var configuredBaseURL: URL {
        guard
            let value = UserDefaults.standard.string(forKey: serverBaseURLKey),
            let url = URL(string: value),
            isAllowedServerURL(url)
        else {
            return productionBaseURL
        }

        return url
    }

    static func makeClient() -> MagonoteAPIClient {
        MagonoteAPIClient(
            baseURL: configuredBaseURL,
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
