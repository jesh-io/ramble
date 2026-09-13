import XCTest
@testable import RambleAnalytics

final class CollectorTests: XCTestCase {
    actor Transport: AnalyticsTransport {
        var batches: [EventBatch] = []
        var result: DeliveryResult = .accepted
        func setResult(_ value: DeliveryResult) { result = value }
        func deliver(_ batch: EventBatch) async throws -> DeliveryResult {
            batches.append(batch)
            return result
        }
        func sent() -> [EventBatch] { batches }
    }
    private func location() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("queue.json") }
    private let event = AnalyticsEvent(schemaVersion: 1, name: "app_opened", properties: [:])

    func testDurableEnqueueRestartAndBatchAcknowledgment() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transport = Transport()
        var collector: PersistentEventCollector? = try PersistentEventCollector(fileURL: url, transport: transport, batchSize: 2, flushInterval: 3600)
        collector!.setEnabled(true)
        for _ in 0..<3 { collector!.send(event) }
        XCTAssertEqual(collector!.pendingCount, 3)
        collector = nil
        let resumed = try PersistentEventCollector(fileURL: url, transport: transport, batchSize: 2, flushInterval: 3600)
        await resumed.flush()
        let beforeConsent = await transport.sent()
        XCTAssertTrue(beforeConsent.isEmpty)
        resumed.setEnabled(true)
        await resumed.flush()
        XCTAssertEqual(resumed.pendingCount, 1)
        await resumed.flush()
        XCTAssertEqual(resumed.pendingCount, 0)
        let sent = await transport.sent()
        XCTAssertEqual(sent.map { $0.events.count }, [2, 1])
    }
    func testRetryStateAndIDsSurviveRestart() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transport = Transport()
        await transport.setResult(.retry(after: 300))
        var collector: PersistentEventCollector? = try PersistentEventCollector(fileURL: url, transport: transport, flushInterval: 3600)
        collector!.setEnabled(true)
        collector!.send(event)
        let now = Date()
        await collector!.flush(now: now)
        collector = nil
        let resumed = try PersistentEventCollector(fileURL: url, transport: transport, flushInterval: 3600)
        resumed.setEnabled(true)
        await resumed.flush(now: now.addingTimeInterval(10))
        let first = await transport.sent()
        XCTAssertEqual(first.count, 1)
        await transport.setResult(.accepted)
        await resumed.flush(now: now.addingTimeInterval(301))
        let second = await transport.sent()
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(first[0].events[0].id, second[1].events[0].id)
        XCTAssertEqual(resumed.pendingCount, 0)
    }
    func testOptOutClearsDiskAndBlocksDelivery() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transport = Transport()
        let collector = try PersistentEventCollector(fileURL: url, transport: transport, flushInterval: 3600)
        collector.setEnabled(true)
        collector.send(event)
        collector.reset()
        collector.send(event)
        await collector.flush()
        XCTAssertEqual(collector.pendingCount, 0)
        let sent = await transport.sent()
        XCTAssertTrue(sent.isEmpty)
        let resumed = try PersistentEventCollector(fileURL: url, transport: transport, flushInterval: 3600)
        XCTAssertEqual(resumed.pendingCount, 0)
    }
    func testQueueLimitAndPermanentRejection() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transport = Transport()
        await transport.setResult(.rejected)
        let collector = try PersistentEventCollector(fileURL: url, transport: transport, maxEvents: 2, flushInterval: 3600)
        collector.setEnabled(true)
        for _ in 0..<5 { collector.send(event) }
        XCTAssertEqual(collector.pendingCount, 2)
        await collector.flush()
        XCTAssertEqual(collector.pendingCount, 0)
    }

    func testExpiredEventsAreNotDelivered() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let transport = Transport()
        let collector = try PersistentEventCollector(fileURL: url, transport: transport, maxAge: 1, flushInterval: 3600)
        collector.setEnabled(true)
        collector.send(event)
        await collector.flush(now: Date().addingTimeInterval(2))
        XCTAssertEqual(collector.pendingCount, 0)
        let sent = await transport.sent()
        XCTAssertTrue(sent.isEmpty)
    }
}
