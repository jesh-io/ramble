import Foundation
import AppKit
import TalkyCore
import TalkyKit

let usage = """
talky — local voice-to-text

USAGE:
  talky <media-file> [--raw] [--json] [--copy]   Transcribe an audio/video file
  talky toggle | start | stop                    Control the Talky menu bar app
  talky clean [text]                             Clean text (arg or stdin) with the active model
  talky history [n]                              Show last n dictations, raw vs cleaned (default 3)
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

case "recordings":
    print(RecordingStore.baseDir.path)

case "models":
    let config = TalkyConfig.load()
    print("cleanup: \(config.cleanup.enabled ? "enabled" : "disabled")")
    for provider in config.cleanup.providers {
        let active = provider.id == config.cleanup.provider ? "* " : "  "
        let key = provider.apiKeyEnv.map { " (key: $\($0))" } ?? ""
        print("\(active)\(provider.id): \(provider.model) @ \(provider.baseURL)\(key)")
    }

case "use":
    guard args.count > 1 else { fail("usage: talky use <provider-id>") }
    var config = TalkyConfig.load()
    let id = args[1]
    guard config.cleanup.providers.contains(where: { $0.id == id }) else {
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
    if args.count > 1 {
        input = args.dropFirst().joined(separator: " ")
    } else {
        input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        fail("No input text. Pass as argument or pipe via stdin.")
    }
    Task {
        do {
            let cleaned = try await TalkyKit.cleanText(input, config: config)
            print(cleaned)
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
