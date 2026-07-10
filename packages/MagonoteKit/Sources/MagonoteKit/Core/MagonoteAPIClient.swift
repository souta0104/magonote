import Foundation

/// Thin HTTP client for the magonote API. Tool-specific calls (e.g. Reader)
/// are added as extensions in their own file (see `Reader/ReaderAPI.swift`),
/// following the pattern documented in the design spec.
public struct MagonoteAPIClient: Sendable {
    let baseURL: URL
    let tokenProvider: any AuthTokenProvider
    let session: URLSession

    public init(baseURL: URL, tokenProvider: any AuthTokenProvider, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// GET request with optional query items. Decodes the JSON response body as `Response`.
    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        let data = try await send(method: "GET", path: path, query: query, body: nil)
        return try decodeResponse(data)
    }

    /// POST request with an Encodable JSON body. Decodes the JSON response body as `Response`.
    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let encodedBody: Data
        do {
            encodedBody = try JSONCoding.apiEncoder.encode(body)
        } catch {
            throw APIError.decoding(error)
        }
        let data = try await send(method: "POST", path: path, query: [], body: encodedBody)
        return try decodeResponse(data)
    }

    /// POST request with no request body (e.g. archive/unarchive). Decodes the JSON response body as `Response`.
    func post<Response: Decodable>(_ path: String) async throws -> Response {
        let data = try await send(method: "POST", path: path, query: [], body: nil)
        return try decodeResponse(data)
    }

    /// Builds and executes the HTTP request, injecting the Bearer token and
    /// mapping non-2xx responses / transport failures to `APIError`.
    private func send(method: String, path: String, query: [URLQueryItem], body: Data?) async throws -> Data {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.network(URLError(.badURL))
        }
        // baseURL に末尾スラッシュがあっても "//api/..." にならないよう、結合前に取り除く
        // (path 引数は常に "/" 始まり)
        var basePath = components.path
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        components.path = basePath + path
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError.network(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        let token = try await tokenProvider.idToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.network(URLError(.badServerResponse))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let envelope = try? JSONCoding.apiDecoder.decode(APIErrorEnvelope.self, from: data) {
                throw APIError(envelope: envelope, status: httpResponse.statusCode)
            }
            throw APIError.server(
                status: httpResponse.statusCode,
                message: "Unexpected error response (status \(httpResponse.statusCode))"
            )
        }

        return data
    }

    private func decodeResponse<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONCoding.apiDecoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
