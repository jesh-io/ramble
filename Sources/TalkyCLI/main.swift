import Foundation
import AppKit
import TalkyCore
import TalkyKit
import TalkyProviders
import TalkyClean

let usage = """
talky — local voice-to-text

USAGE:
  talky <media-file> [--raw] [--json] [--copy]   Transcribe an audio/video file
  talky toggle | start | stop                    Control the Talky menu bar app
  talky clean [text]                             Clean text (arg or stdin) with the active model
  talky history [n]                              Show last n dictations, raw vs cleaned (default 3)
  talky audit [n]                                Diff-audit cleanup of last n dictations for hallucinations
  talky learn "<Term> = <misheard1>, <m2>"       Add a vocabulary term (= part optional)
  talky vocab                                    List vocabulary entries
  talky eval [provider-id]                       Score cleanup against your corrected dictations
  talky usage                                    Usage & cost per day per model
  talky models                                   List cleanup model providers
  talky use <provider-id>                        Set the active cleanup provider
  talky download                                 Pre-download the on-device speech model
  talky config                                   Print the config file path

FILE OPTIONS:
  --raw    Skip LLM cleanup, print the raw transcript
  --json   Print segments as JSON (timestamps, future speaker labels)
  --copy   Also copy the result to the clipboard

Config: ~/.config/talky/config.json
"""

func fail(_ message: String) -> Never {
    // fputs never raises, unlike FileHandle.write which throws ObjC
    // exceptions on closed/odd stderr.
    fputs(message + "\n", stderr)
    exit(1)
}

func postAppCommand(_ command: String) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("io.talky.\(command)"),
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    print("sent \(command)")
}

func copyToClipboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let first = args.first else {
    print(usage)
    exit(0)
}

let semaphore = DispatchSemaphore(value: 0)

switch first {
case "-h", "--help", "help":
    print(usage)

case "toggle", "start", "stop":
    postAppCommand(first)

case "config":
    print(TalkyConfig.fileURL.path)
    _ = TalkyConfig.load()

case "history":
    let count = args.count > 1 ? (Int(args[1]) ?? 3) : 3
    let entries = DictationHistory.last(count)
    if entries.isEmpty {
        print("No dictation history yet (\(DictationHistory.fileURL.path))")
    }
    for entry in entries {
        print("── \(entry.timestamp)  [\(entry.provider ?? "no cleanup")]")
        print("raw:     \(entry.raw)")
        print("cleaned: \(entry.cleaned)")
        print()
    }
    print("recordings (audio + per-session transcripts): \(RecordingStore.baseDir.path)")

case "audit":
    let count = args.count > 1 ? (Int(args[1]) ?? 5) : 5
    let config = TalkyConfig.load()
    let sessions = RecordingStore.sessions(limit: count)
    guard !sessions.isEmpty else { print("No sessions yet."); break }
    for session in sessions {
        guard let r = session.record, let cleaned = r.cleaned else { continue }
        let diff = TranscriptDiff(input: r.raw, output: cleaned)
        let long = diff.insertedRuns.filter { $0.wordCount > config.cleanup.maxInsertedRun }
        let verdict = long.isEmpty ? "ok" : "HALLUCINATION SUSPECTED"
        print(String(format: "── %@  [%@]  similarity %.1f%%  +%d/-%d words  %@",
                     session.dir.lastPathComponent, r.provider ?? "raw",
                     diff.similarity * 100,
                     diff.insertedRuns.reduce(0) { $0 + $1.wordCount }, diff.deletedWords, verdict))
        if let note = r.guardNote { print("   guard: \(note)") }
        for run in long { print("   inserted (\(run.wordCount) words): \"\(run.text.prefix(120))\"") }
    }

case "guard":
    // QA: talky guard <raw.txt> <cleaned.txt> — run the diff guard on two files.
    guard args.count > 2,
          let raw = try? String(contentsOfFile: args[1], encoding: .utf8),
          let cleaned = try? String(contentsOfFile: args[2], encoding: .utf8) else {
        fail("usage: talky guard <raw.txt> <cleaned.txt>")
    }
    let config = TalkyConfig.load()
    let result = CleanupValidator.guardOutput(raw: raw, cleaned: cleaned, maxInsertedRun: config.cleanup.maxInsertedRun)
    print(String(format: "similarity %.1f%%  removed %d word(s)  rejected: %@", result.similarity * 100, result.removedWords, result.rejected ? "yes" : "no"))
    for run in result.removedRuns { print("  stripped: \"\(run.prefix(160))\"") }
    print("--- repaired text:\n" + result.text)

case "recordings":
    print(RecordingStore.baseDir.path)

case "usage":
    let config = TalkyConfig.load()
    let entries = UsageLog.entries()
    guard !entries.isEmpty else {
        print("No usage recorded yet (\(UsageLog.fileURL.path))")
        break
    }
    struct Key: Hashable { let day: String; let model: String }
    var agg: [Key: (seconds: Double, tokensIn: Int, tokensOut: Int)] = [:]
    for entry in entries {
        let key = Key(day: entry.day, model: entry.model)
        var a = agg[key] ?? (0, 0, 0)
        a.seconds += entry.seconds ?? 0
        a.tokensIn += entry.tokensIn ?? 0
        a.tokensOut += entry.tokensOut ?? 0
        agg[key] = a
    }
    func cost(model: String, tokensIn: Int, tokensOut: Int) -> Double? {
        guard let p = ProviderRegistry.allCleanupProviders(config).first(where: { $0.model == model }),
              p.inputCostPerMTok != nil || p.outputCostPerMTok != nil else { return nil }
        return Double(tokensIn) / 1e6 * (p.inputCostPerMTok ?? 0)
            + Double(tokensOut) / 1e6 * (p.outputCostPerMTok ?? 0)
    }
    var dayCost: [String: Double] = [:]
    print("day         model                          audio     tok in   tok out  cost")
    for (key, a) in agg.sorted(by: { ($0.key.day, $0.key.model) > ($1.key.day, $1.key.model) }) {
        let c = cost(model: key.model, tokensIn: a.tokensIn, tokensOut: a.tokensOut)
        if let c { dayCost[key.day, default: 0] += c }
        let audio = a.seconds > 0 ? String(format: "%.0fs", a.seconds) : ""
        let tin = a.tokensIn > 0 ? "\(a.tokensIn)" : ""
        let tout = a.tokensOut > 0 ? "\(a.tokensOut)" : ""
        let costStr = c.map { String(format: "$%.4f", $0) } ?? "local"
        print(key.day.padding(toLength: 12, withPad: " ", startingAt: 0)
            + key.model.padding(toLength: 31, withPad: " ", startingAt: 0)
            + audio.padding(toLength: 10, withPad: " ", startingAt: 0)
            + tin.padding(toLength: 9, withPad: " ", startingAt: 0)
            + tout.padding(toLength: 9, withPad: " ", startingAt: 0)
            + costStr)
    }
    let paidDays = dayCost.filter { $0.value > 0 }
    if !paidDays.isEmpty {
        let avg = paidDays.values.reduce(0, +) / Double(paidDays.count)
        print(String(format: "\navg $%.4f per active day → ~$%.2f / 30 days", avg, avg * 30))
    }

case "learn":
    guard args.count > 1 else { fail("usage: talky learn \"Term = misheard1, misheard2\"") }
    guard let entry = TalkyConfig.vocabularyEntry(from: args.dropFirst().joined(separator: " ")) else {
        fail("Could not parse vocabulary entry")
    }
    var config = TalkyConfig.load()
    config.addVocabulary([entry])
    do {
        try config.save()
        print("learned: \(entry)")
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("io.talky.reload"), object: nil, userInfo: nil, deliverImmediately: true)
    } catch {
        fail("Could not save config: \(error.localizedDescription)")
    }

case "vocab":
    for entry in TalkyConfig.load().vocabulary {
        print("- \(entry)")
    }

case "eval":
    var config = TalkyConfig.load()
    if args.count > 1 {
        guard ProviderRegistry.allCleanupProviders(config).contains(where: { $0.id == args[1] }) else {
            fail("Unknown provider '\(args[1])'")
        }
        config.cleanup.provider = args[1]
    }
    let goldenSessions = RecordingStore.sessions(limit: 1000).filter { $0.record?.revision != nil }
    guard !goldenSessions.isEmpty else {
        fail("""
            No corrected dictations to score against yet.
            Use the menu bar's "Fix Last Dictation…" to correct outputs — each correction becomes a golden eval case.
            """)
    }
    let cfg = config
    Task {
        func words(_ s: String) -> [String] {
            s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        }
        // Word error rate: word-level Levenshtein / reference length.
        func wer(reference: String, hypothesis: String) -> Double {
            let r = words(reference), h = words(hypothesis)
            guard !r.isEmpty else { return h.isEmpty ? 0 : 1 }
            var prev = Array(0...h.count)
            for i in 1...r.count {
                var row = [i] + Array(repeating: 0, count: h.count)
                for j in 1...h.count {
                    row[j] = min(
                        prev[j] + 1,
                        row[j - 1] + 1,
                        prev[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
                }
                prev = row
            }
            return Double(prev[h.count]) / Double(r.count)
        }

        print("Scoring \(goldenSessions.count) corrected dictation(s) with provider '\(cfg.cleanup.provider)'…\n")
        var total = 0.0
        var count = 0
        for session in goldenSessions {
            guard let record = session.record, let golden = record.revision else { continue }
            let output = (try? await TalkyKit.cleanText(record.raw, config: cfg)) ?? record.raw
            let score = wer(reference: golden, hypothesis: output)
            total += score
            count += 1
            print(String(format: "WER %.3f  %@", score, session.dir.lastPathComponent))
        }
        let mean = total / Double(max(count, 1))
        print(String(format: "\nmean WER: %.3f across %d case(s)  (lower is better)", mean, count))
        semaphore.signal()
    }
    semaphore.wait()

case "models":
    let config = TalkyConfig.load()
    print("cleanup: \(config.cleanup.enabled ? "enabled" : "disabled")")
    for provider in ProviderRegistry.allCleanupProviders(config) {
        let active = provider.id == config.cleanup.provider ? "* " : "  "
        let key = provider.apiKeyEnv.map { " (key: $\($0))" } ?? ""
        print("\(active)\(provider.id): \(provider.model) @ \(provider.baseURL)\(key)")
    }

case "use":
    guard args.count > 1 else { fail("usage: talky use <provider-id>") }
    var config = TalkyConfig.load()
    let id = args[1]
    guard ProviderRegistry.allCleanupProviders(config).contains(where: { $0.id == id }) else {
        fail("Unknown provider '\(id)'. Run `talky models` to list, or add it to \(TalkyConfig.fileURL.path)")
    }
    config.cleanup.provider = id
    do {
        try config.save()
        print("active cleanup provider: \(id)")
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("io.talky.reload"), object: nil, userInfo: nil, deliverImmediately: true)
    } catch {
        fail("Could not save config: \(error.localizedDescription)")
    }

case "download":
    let config = TalkyConfig.load()
    Task {
        do {
            print("Checking/downloading on-device speech model for \(config.locale)…")
            try await TalkyKit.makeDefaultTranscriber(config: config).prepare()
            print("Speech model ready.")
        } catch {
            fail("Model download failed: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()

case "clean":
    let config = TalkyConfig.load()
    let input: String
    let textArgs = args.dropFirst().filter { $0 != "--incremental" }
    if !textArgs.isEmpty {
        input = textArgs.joined(separator: " ")
    } else {
        input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        fail("No input text. Pass as argument or pipe via stdin.")
    }
    Task {
        do {
            if args.contains("--incremental") {
                // Simulate live dictation: sentences "finalize" one at a time.
                guard let provider = ProviderRegistry.activeCleanupProvider(config) else {
                    fail("No cleanup provider configured")
                }
                let inc = IncrementalCleaner(config: config, provider: provider)
                var sofar = ""
                let sentences = input.replacingOccurrences(of: "--incremental", with: "")
                    .components(separatedBy: ". ")
                for (i, s) in sentences.enumerated() {
                    sofar += (sofar.isEmpty ? "" : ". ") + s
                    if i < sentences.count - 1 {
                        await inc.feed(finalized: sofar)
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                let started = Date()
                let out = await inc.finish(finalized: sofar)
                fputs(String(format: "final tail wait: %.2fs\n", Date().timeIntervalSince(started)), stderr)
                for n in await inc.guardNotes { fputs("guard: \(n)\n", stderr) }
                print(out)
            } else {
                let cleaned = try await TalkyKit.cleanText(input, config: config)
                print(cleaned)
            }
        } catch {
            fail("Cleanup failed: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()

default:
    // Treat as a media file path.
    var flags = Set<String>()
    var path = first
    for arg in args.dropFirst() {
        if arg.hasPrefix("--") { flags.insert(arg) } else { path = arg }
    }
    if first.hasPrefix("--"), args.count > 1 {
        // allow flags before the path
        path = args.first { !$0.hasPrefix("--") } ?? first
        flags = Set(args.filter { $0.hasPrefix("--") })
    }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: url.path) else {
        fail("Not a command or file: \(path)\n\n\(usage)")
    }

    let config = TalkyConfig.load()
    let wantClean = !flags.contains("--raw")
    Task {
        do {
            FileHandle.standardError.write(Data("Transcribing \(url.lastPathComponent)…\n".utf8))
            let result = try await FileTranscription.transcribe(
                url: url,
                config: config,
                clean: wantClean,
                onSegment: { segment in
                    FileHandle.standardError.write(Data(".".utf8))
                }
            )
            FileHandle.standardError.write(Data("\n".utf8))
            if let warning = result.warning {
                FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
            }

            let output: String
            if flags.contains("--json") {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                struct JSONOut: Codable {
                    let text: String
                    let cleaned: String?
                    let segments: [TranscriptSegment]
                }
                let payload = JSONOut(
                    text: result.transcript.text,
                    cleaned: result.cleaned,
                    segments: result.transcript.segments
                )
                output = String(data: try encoder.encode(payload), encoding: .utf8) ?? ""
            } else {
                output = result.bestText
            }

            print(output)
            if flags.contains("--copy") {
                copyToClipboard(flags.contains("--json") ? output : result.bestText)
                FileHandle.standardError.write(Data("(copied to clipboard)\n".utf8))
            }
        } catch {
            fail("Transcription failed: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
}
