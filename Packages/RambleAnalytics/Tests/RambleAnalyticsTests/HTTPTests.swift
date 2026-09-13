import Foundation
import XCTest
@testable import RambleAnalytics

final class HTTPTests: XCTestCase {
    final class Stub: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let code = Int(request.url!.lastPathComponent) ?? 200
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "120"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
    func testStatusClassification() async throws {
        let batch = EventBatch(schemaVersion: 1, batchID: UUID(), events: [])
        for status in [200, 202, 204, 400, 401, 413, 408, 429, 503] {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [Stub.self]
            let adapter = try HTTPAnalyticsTransport(endpoint: URL(string: "https://example.com/\(status)")!, configuration: config)
            let result = try await adapter.deliver(batch)
            switch (status, result) {
            case (200, .accepted), (202, .accepted), (204, .accepted),
                 (400, .rejected), (401, .rejected), (413, .rejected): break
            case (408, .retry(let delay)), (429, .retry(let delay)), (503, .retry(let delay)):
                XCTAssertEqual(delay, 120)
            default: XCTFail("Incorrect delivery classification for \(status)")
            }
        }
    }
    func testWireFormatContainsOnlyApprovedMetadata() throws {
        let event = AnalyticsEvent(schemaVersion: 1, name: "dictation_completed", properties: ["duration_seconds_bucket": "lt_30"])
        let batch = EventBatch(schemaVersion: 1, batchID: UUID(), events: [CollectedEvent(id: UUID(), occurredAt: Date(), event: event)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(batch)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schemaVersion", "batchID", "events"])
        let events = try XCTUnwrap(json["events"] as? [[String: Any]])
        XCTAssertEqual(Set(events[0].keys), ["id", "occurredAt", "event"])
    }
}
