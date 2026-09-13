import Foundation
import OSLog

/// Single-process durable queue. Give each process its own queue URL.
/// Delivery is at least once; event IDs survive retries and process restarts.
public final class PersistentEventCollector: AnalyticsAdapter, @unchecked Sendable {
    private struct Queue: Codable {
        var events: [CollectedEvent] = []
        var failures = 0
        var nextAttempt = Date.distantPast
    }
    private let lock = NSLock()
    private let fileURL: URL
    private let transport: any AnalyticsTransport
    private let batchSize: Int
    private let maxEvents: Int
    private let maxAge: TimeInterval
    private let interval: TimeInterval
    private var queue: Queue
    private var generation = 0
    private var inFlight = false
    private var enabled = false
    private var worker: Task<Void, Never>?
    private let logger = Logger(subsystem: "io.ramble.analytics", category: "collector")

    public init(fileURL: URL, transport: any AnalyticsTransport, batchSize: Int = 50,
                maxEvents: Int = 1000, maxAge: TimeInterval = 7 * 86400,
                flushInterval: TimeInterval = 30) throws {
        precondition(batchSize > 0 && maxEvents > 0 && maxAge > 0 && flushInterval > 0)
        self.fileURL = fileURL
        self.transport = transport
        self.batchSize = min(batchSize, maxEvents)
        self.maxEvents = maxEvents
        self.maxAge = maxAge
        interval = flushInterval
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            // Fail closed on corrupt queues; never interpret unknown payloads.
            queue = (try? JSONDecoder().decode(Queue.self, from: data)) ?? Queue()
        } else { queue = Queue() }
        queue.events.removeAll { $0.occurredAt < Date().addingTimeInterval(-maxAge) }
        queue.events = Array(queue.events.suffix(maxEvents))
        try persist()
    }
    deinit { worker?.cancel() }

    public func send(_ event: AnalyticsEvent) {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return }
        queue.events.removeAll { $0.occurredAt < Date().addingTimeInterval(-maxAge) }
        queue.events.append(CollectedEvent(id: UUID(), occurredAt: Date(), event: event))
        queue.events = Array(queue.events.suffix(maxEvents))
        do { try persist() }
        catch {
            queue.events.removeLast()
            logger.error("Analytics queue write failed; event discarded.")
        }
    }

    /// Opt-out clears the durable queue before returning and cancels networking.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        enabled = false
        worker?.cancel()
        worker = nil
        queue = Queue()
        do { try persist() }
        catch {
            try? FileManager.default.removeItem(at: fileURL)
            logger.error("Analytics queue reset could not be persisted.")
        }
    }

    public var pendingCount: Int { lock.withLock { queue.events.count } }

    public func setEnabled(_ value: Bool) {
        if !value { reset(); return }
        lock.withLock {
            enabled = true
            if worker == nil { startWorker() }
        }
    }

    private func startWorker() {
        worker = Task { [weak self, interval] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                await self?.flush()
            }
        }
    }

    /// At most one batch is in flight. Retry state is persisted across crashes.
    public func flush(now: Date = Date()) async {
        let snapshot: (EventBatch, Int)? = lock.withLock {
            guard enabled, !inFlight, now >= queue.nextAttempt else { return nil }
            queue.events.removeAll { $0.occurredAt < now.addingTimeInterval(-maxAge) }
            guard !queue.events.isEmpty else { try? persist(); return nil }
            inFlight = true
            return (EventBatch(schemaVersion: 1, batchID: UUID(), events: Array(queue.events.prefix(batchSize))), generation)
        }
        guard let (batch, currentGeneration) = snapshot else { return }
        let result: DeliveryResult
        do { result = try await transport.deliver(batch) }
        catch { result = .retry(after: nil) }
        lock.withLock {
            inFlight = false
            guard currentGeneration == generation else { return }
            switch result {
            case .accepted, .rejected:
                let ids = Set(batch.events.map(\.id))
                queue.events.removeAll { ids.contains($0.id) }
                queue.failures = 0
                queue.nextAttempt = .distantPast
                if case .rejected = result { logger.error("Analytics batch rejected by endpoint; discarded.") }
            case .retry(let retryAfter):
                queue.failures = min(queue.failures + 1, 12)
                let delay = min(3600, pow(2, Double(queue.failures)) * 5) * Double.random(in: 0.8...1.2)
                queue.nextAttempt = now.addingTimeInterval(max(delay, retryAfter ?? 0))
            }
            do { try persist() }
            catch { logger.error("Analytics delivery state could not be saved; duplicates may be retried after restart.") }
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(queue).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
