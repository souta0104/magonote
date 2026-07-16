@testable import Magonote
import XCTest

final class APIClientFactoryTests: XCTestCase {
    private var originalValue: String?

    override func setUp() {
        super.setUp()
        originalValue = UserDefaults.standard.string(
            forKey: APIClientFactory.serverBaseURLKey
        )
    }

    override func tearDown() {
        if let originalValue {
            UserDefaults.standard.set(
                originalValue,
                forKey: APIClientFactory.serverBaseURLKey
            )
        } else {
            UserDefaults.standard.removeObject(
                forKey: APIClientFactory.serverBaseURLKey
            )
        }
        super.tearDown()
    }

    func testUsesHTTPSURL() {
        UserDefaults.standard.set(
            "https://example.com",
            forKey: APIClientFactory.serverBaseURLKey
        )

        XCTAssertEqual(
            APIClientFactory.configuredBaseURL.absoluteString,
            "https://example.com"
        )
    }

    func testAllowsLocalHTTPURL() {
        UserDefaults.standard.set(
            "http://127.0.0.1:8787",
            forKey: APIClientFactory.serverBaseURLKey
        )

        XCTAssertEqual(
            APIClientFactory.configuredBaseURL.absoluteString,
            "http://127.0.0.1:8787"
        )
    }

    func testRejectsRemoteHTTPURL() {
        UserDefaults.standard.set(
            "http://example.com",
            forKey: APIClientFactory.serverBaseURLKey
        )

        XCTAssertEqual(
            APIClientFactory.configuredBaseURL,
            APIClientFactory.productionBaseURL
        )
    }
}
