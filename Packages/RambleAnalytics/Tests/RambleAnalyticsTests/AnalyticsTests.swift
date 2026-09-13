import XCTest
@testable import RambleAnalytics

final class AnalyticsTests: XCTestCase {
    final class Spy: AnalyticsAdapter, @unchecked Sendable {
        var events: [AnalyticsEvent] = []
        var resets = 0
        func send(_ event: AnalyticsEvent) { events.append(event) }
        func reset() { resets += 1 }
    }
    override func tearDown() { Analytics.configure(enabled: false) }
    func testConsentAndRevocation() {
        let spy = Spy()
        Analytics.configure(enabled: false, adapter: spy)
        Analytics.appOpened()
        XCTAssertTrue(spy.events.isEmpty)
        Analytics.configure(enabled: true)
        Analytics.appOpened()
        XCTAssertEqual(spy.events.count, 1)
        Analytics.configure(enabled: false)
        Analytics.appOpened()
        XCTAssertEqual(spy.events.count, 1)
        XCTAssertGreaterThan(spy.resets, 0)
    }
    func testRedactionAndBuckets() {
        let spy = Spy()
        Analytics.configure(enabled: true, adapter: spy)
        Analytics.dictationStarted(source: .microphone, provider: "private-account", model: "secret-project-model")
        XCTAssertEqual(spy.events[0].properties["provider"], "custom")
        XCTAssertEqual(spy.events[0].properties["model"], "custom")
        Analytics.dictationCompleted(source: .microphone, outcome: .success, durationSeconds: 22, characterCount: 127)
        XCTAssertEqual(spy.events[1].properties["duration_seconds_bucket"], "lt_30")
        XCTAssertEqual(spy.events[1].properties["character_count_bucket"], "lt_200")
    }
    func testRejectsInsecureEndpoints() {
        XCTAssertThrowsError(try HTTPAnalyticsTransport(endpoint: URL(string: "http://example.com/events")!))
        XCTAssertThrowsError(try HTTPAnalyticsTransport(endpoint: URL(string: "https://user:secret@example.com/events")!))
    }
    func testRetryAfter() {
        XCTAssertEqual(HTTPAnalyticsTransport.retryAfter("120"), 120)
        XCTAssertNil(HTTPAnalyticsTransport.retryAfter("invalid"))
        XCTAssertEqual(HTTPAnalyticsTransport.retryAfter("Thu, 01 Jan 1970 00:02:00 GMT", now: Date(timeIntervalSince1970: 0)), 120)
    }
}
