import Foundation

/// Shared JSON coding used by all MagonoteKit API calls. The magonote API
/// serializes timestamps as unix milliseconds and uses camelCase keys
/// natively, so no key conversion strategy is needed.
enum JSONCoding {
    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let milliseconds = Int64(date.timeIntervalSince1970 * 1_000)
            try container.encode(milliseconds)
        }
        return encoder
    }()
}
