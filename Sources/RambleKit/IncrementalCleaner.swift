import Foundation
import RambleAnalytics
import RambleCore
import RambleClean
import RambleProviders

/// Cleans a transcript in chunks *while dictation is still running*, so
/// the end-of-dictation wait is only the last chunk instead of the whole
/// text. Chunks are cut at sentence boundaries once `chunkWords` words are
/// finalized; each chunk is cleaned with the previous cleaned sentence as
/// read-only context and passed through the diff guard.
public actor IncrementalCleaner {
    private let config: RambleConfig
    private let provider: CleanupProvider
    private var cleanedChunks: [String] = []
    private var consumedWords = 0          // words of finalized text already dispatched
    private var inFlight: Task<Void, Never>?
    public private(set) var guardNotes: [String] = []
    public private(set) var usedProvider: String?

    public init(config: RambleConfig, provider: CleanupProvider) {
        self.config = config
        self.provider = provider
    }

    /// Feed the full finalized-so-far transcript. Dispatches a chunk when
    /// enough new words have accumulated and no chunk is in flight.
    public func feed(finalized: String) async {
        guard inFlight == nil else { return }
        let words = finalized.split(whereSeparator: \.isWhitespace).map(String.init)
        let pending = words.dropFirst(consumedWords)
        guard pending.count >= config.cleanup.chunkWords else { return }
        // Cut at the last sentence end within the pending words so chunks
        // don't split mid-sentence.
        var cut = pending.count
        for (i, w) in pending.enumerated().reversed() where w.hasSuffix(".") || w.hasSuffix("?") || w.hasSuffix("!") {
            cut = i + 1
            break
        }
        guard cut >= max(8, config.cleanup.chunkWords / 2) else { return }
        let chunk = pending.prefix(cut).joined(separator: " ")
        consumedWords += cut
        let context = cleanedChunks.last.map { lastSentence(of: $0) }
        inFlight = Task { [weak self] in
            guard let self else { return }
            let cleaned = await self.cleanChunk(chunk, context: context)
            await self.append(cleaned)
        }
    }

    /// Cleans whatever remains after `finalized` and returns the full text.
    public func finish(finalized: String) async -> String {
        await inFlight?.value
        inFlight = nil
        let words = finalized.split(whereSeparator: \.isWhitespace).map(String.init)
        let tail = words.dropFirst(consumedWords).joined(separator: " ")
        if !tail.isEmpty {
            let context = cleanedChunks.last.map { lastSentence(of: $0) }
            cleanedChunks.append(await cleanChunk(tail, context: context))
        }
        return cleanedChunks.joined(separator: " ")
            .replacingOccurrences(of: " \n", with: "\n")
    }

    private func append(_ text: String) {
        cleanedChunks.append(text)
        inFlight = nil
    }

    private func cleanChunk(_ raw: String, context: String?) async -> String {
        let started = Date()
        let base = Vocabulary.applyKnownMishearings(
            to: SpokenCommands.apply(to: raw), vocabulary: config.vocabulary)
        do {
            var prompt = config.effectiveCleanupPrompt
            if let context {
                prompt += """


                You are cleaning ONE CHUNK of a longer dictation. For continuity only, the previous \
                chunk ended with: "\(context)" — do NOT include it in your output. Output only the cleaned \
                version of the chunk you are given.
                """
            }
            let cleaner = try CleanerFactory.make(
                provider: provider, systemPrompt: prompt, timeout: config.cleanup.timeoutSeconds)
            let candidate = try await cleaner.clean(base)
            let guarded = CleanupValidator.guardOutput(
                raw: base, cleaned: candidate, maxInsertedRun: config.cleanup.maxInsertedRun, minSimilarity: config.cleanup.minSimilarity)
            if let note = guarded.note { guardNotes.append(note) }
            Analytics.cleanupCompleted(provider: provider.analyticsProvider, model: provider.model,
                outcome: .success, latencySeconds: Date().timeIntervalSince(started), rejected: guarded.rejected)
            usedProvider = provider.id
            return guarded.text
        } catch {
            Analytics.cleanupCompleted(provider: provider.analyticsProvider, model: provider.model,
                outcome: Task.isCancelled ? .cancelled : .failed, latencySeconds: Date().timeIntervalSince(started), rejected: false)
            guardNotes.append("chunk cleanup failed: \(error.localizedDescription)")
            return base
        }
    }

    private func lastSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "[.!?]\\s+(?=[^.!?]*$)", options: .regularExpression) {
            return String(trimmed[range.upperBound...])
        }
        return String(trimmed.suffix(160))
    }
}
