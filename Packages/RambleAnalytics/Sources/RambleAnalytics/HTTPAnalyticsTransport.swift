import Foundation

public struct CollectedEvent: Codable, Sendable, Equatable {
    public let id: UUID
    public let occurredAt: Date
    public let event: AnalyticsEvent
}
public struct EventBatch: Codable, Sendable {
    public let schemaVersion: Int
    public let batchID: UUID
    public let events: [CollectedEvent]
}
public enum DeliveryResult: Sendable {
    case accepted
    case retry(after: TimeInterval?)
    case rejected
}
public protocol AnalyticsTransport: Sendable {
    func deliver(_ batch: EventBatch) async throws -> DeliveryResult
}

/// HTTPS JSON POST. Success means the server durably accepted the entire batch.
/// Servers MUST deduplicate by event id (a batch can be retried after a crash).
public final class HTTPAnalyticsTransport: AnalyticsTransport, @unchecked Sendable {
    private let endpoint: URL
    private let bearerToken: String?
    private let session: URLSession
    private let delegate = NoRedirects()

    public init(endpoint: URL, bearerToken: String? = nil, configuration: URLSessionConfiguration = .ephemeral) throws {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
              endpoint.password == nil, endpoint.fragment == nil else {
            throw URLError(.badURL)
        }
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func deliver(_ batch: EventBatch) async throws -> DeliveryResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(batch.batchID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(batch)
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch response.statusCode {
        case 200..<300: return .accepted
        case 408, 425, 429, 500...599:
            return .retry(after: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
        default: return .rejected
        }
    }
    static func retryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, $0.timeIntervalSince(now)) }
    }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
