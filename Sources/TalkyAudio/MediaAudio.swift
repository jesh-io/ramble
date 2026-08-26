import Foundation
@preconcurrency import AVFoundation
import TalkyCore

/// Turns any audio or video media file into something an audio-only
/// transcriber can read. Audio files pass through untouched; video
/// containers get their audio track extracted to a temporary .m4a.
public enum MediaAudio {
    public struct Extracted: Sendable {
        public let url: URL
        public let isTemporary: Bool

        /// Deletes the temp file if one was created.
        public func cleanUp() {
            if isTemporary {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    public static func audioFile(for url: URL) async throws -> Extracted {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TalkyError("File not found: \(url.path)")
        }
        // Directly readable audio (wav, m4a, mp3, aiff, caf, flac, ...)?
        if (try? AVAudioFile(forReading: url)) != nil {
            return Extracted(url: url, isTemporary: false)
        }
        // Otherwise treat as a video/container and pull out the audio track.
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw TalkyError("No audio track in \(url.lastPathComponent)")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TalkyError("Cannot extract audio from \(url.lastPathComponent)")
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("talky-\(UUID().uuidString).m4a")
        try await session.export(to: output, as: .m4a)
        return Extracted(url: output, isTemporary: true)
    }
}
