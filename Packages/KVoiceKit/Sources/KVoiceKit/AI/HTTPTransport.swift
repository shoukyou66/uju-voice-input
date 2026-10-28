import Foundation

/// The network seam: production uses `URLSessionTransport`, tests a stub.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 180
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.malformedResponse
        }
        return (data, http)
    }
}

/// Errors from an AI provider or a cloud transcription endpoint.
public enum ProviderError: Error, Equatable, Sendable, LocalizedError {
    case missingAPIKey(ProviderKind)
    case invalidBaseURL
    case insecureBaseURL
    case missingModel
    case unauthorized
    case rateLimited
    case http(status: Int, message: String?)
    case malformedResponse
    case emptyResponse
    case offline
    case unavailable(String)
    case refused

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "請到「設定」加入你的 \(provider.displayName) API 金鑰。"
        case .invalidBaseURL:
            "端點網址無效。"
        case .insecureBaseURL:
            "端點必須使用 HTTPS。"
        case .missingModel:
            "請到「設定」為這個供應商選擇模型。"
        case .unauthorized:
            "供應商拒絕了這組 API 金鑰。"
        case .rateLimited:
            "供應商限制了請求次數，或你的額度已用完。請稍後再試。"
        case .http(let status, let message):
            "供應商回傳錯誤（\(status)）" + (message.map { ": \($0)" } ?? ".")
        case .malformedResponse:
            "供應商傳回的回應 KVoice 無法讀取。"
        case .emptyResponse:
            "供應商沒有回傳文字。"
        case .offline:
            "沒有網路連線。"
        case .unavailable(let reason):
            reason
        case .refused:
            "模型拒絕整理這段文字。"
        }
    }
}

/// URL and response helpers shared by the HTTP providers.
enum HTTP {
    /// Resolves an API root (`https://host/v1`) or a full endpoint to the
    /// endpoint with `suffix`, never appending it twice. A bare host means
    /// the API root `/v1`. HTTPS is required except for loopback hosts.
    static func endpoint(base: URL?, suffix: String) throws -> URL {
        guard let base,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil else {
            throw ProviderError.invalidBaseURL
        }
        switch scheme {
        case "https": break
        case "http" where isLoopback(host): break
        case "http": throw ProviderError.insecureBaseURL
        default: throw ProviderError.invalidBaseURL
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1" }
        if !path.lowercased().hasSuffix(suffix.lowercased()) { path += suffix }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw ProviderError.invalidBaseURL }
        return url
    }

    static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    /// Sends a request and maps transport and HTTP failures.
    static func send(_ request: URLRequest, with transport: any HTTPTransport) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            throw ProviderError.offline
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw ProviderError.unauthorized
        case 429: throw ProviderError.rateLimited
        default: throw ProviderError.http(status: response.statusCode, message: errorMessage(in: data))
        }
    }

    /// The `error.message` most providers put in failure bodies.
    static func errorMessage(in data: Data) -> String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        guard let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message else {
            return nil
        }
        return String(message.prefix(300))
    }

    static func jsonRequest(url: URL, body: some Encodable) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(body)
        return request
    }
}
