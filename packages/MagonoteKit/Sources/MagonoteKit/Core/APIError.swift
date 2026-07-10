import Foundation

/// Errors surfaced by ``MagonoteAPIClient``.
///
/// Server error responses are shaped as `{ "error": { "code": "...", "message": "..." } }`.
/// `APIError` maps the `code` string to a matching case; unknown codes fall
/// back to `.server(status:message:)`.
public enum APIError: Error, Sendable {
    case unauthorized
    case forbidden
    case notFound
    case validation(String)
    case server(status: Int, message: String)
    case network(any Error)
    case decoding(any Error)
}

/// Decodes the API's `{ "error": { "code": "...", "message": "..." } }` envelope.
struct APIErrorEnvelope: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let code: String
        let message: String
    }

    let error: Body
}

extension APIError {
    /// Maps a decoded error envelope + HTTP status to the corresponding `APIError` case.
    ///
    /// Known codes: `unauthorized`, `forbidden`, `not_found`, `validation_error`, `internal`.
    /// Unknown codes fall back to `.server(status:message:)`.
    init(envelope: APIErrorEnvelope, status: Int) {
        switch envelope.error.code {
        case "unauthorized":
            self = .unauthorized
        case "forbidden":
            self = .forbidden
        case "not_found":
            self = .notFound
        case "validation_error":
            self = .validation(envelope.error.message)
        case "internal":
            self = .server(status: status, message: envelope.error.message)
        default:
            self = .server(status: status, message: envelope.error.message)
        }
    }
}
