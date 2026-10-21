// Chat photos and voice notes: the private "chat-media" bucket, under <match_id>/<file>.
// Only the two people in the match can read or add files there, through short-lived
// signed URLs. Photos are blurred until tapped; ones the iPhone flags as nudity
// (Sensitive Content Analysis, on device) are always blurred first.
import AVFoundation
import Foundation
import SensitiveContentAnalysis
import Supabase
import UIKit

enum ChatMedia {
    static let bucket = "chat-media"
    static let blurKey = "jur.blurChatPhotos"

    struct NewMediaMessage: Encodable {
        let matchId: UUID, senderId: UUID, body: String, kind: String, mediaPath: String, mediaMs: Int?
        enum CodingKeys: String, CodingKey {
            case body, kind
            case matchId = "match_id", senderId = "sender_id", mediaPath = "media_path", mediaMs = "media_ms"
        }
    }

    private static func path(_ match: UUID, ext: String) -> String {
        "\(match.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(ext)"
    }

    /// Uploads a photo and posts the message. Throws `photo_too_soon` until you've both written.
    static func sendPhoto(_ data: Data, match: UUID, me: UUID) async throws {
        guard let jpeg = Media.jpeg(from: data) else { throw ServerError(code: "bad_image") }
        let p = path(match, ext: "jpg")
        _ = try await supabase.storage.from(bucket).upload(p, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
        try await post(.init(matchId: match, senderId: me, body: "", kind: "photo", mediaPath: p, mediaMs: nil))
    }

    static func sendVoice(_ file: URL, durationMs: Int, match: UUID, me: UUID) async throws {
        let data = try Data(contentsOf: file)
        let p = path(match, ext: "m4a")
        _ = try await supabase.storage.from(bucket).upload(p, data: data, options: FileOptions(contentType: "audio/m4a"))
        try await post(.init(matchId: match, senderId: me, body: "", kind: "voice", mediaPath: p, mediaMs: durationMs))
    }

    private static func post(_ m: NewMediaMessage) async throws {
        do {
            try await supabase.from("messages").insert(m).execute()
        } catch {
            if "\(error)".contains("photo_too_soon") { throw ServerError(code: "photo_too_soon") }
            throw error
        }
    }

    /// The file's bytes, cached in memory for the session.
    @MainActor private static var cache: [String: Data] = [:]

    @MainActor
    static func data(_ path: String) async throws -> Data {
        if let hit = cache[path] { return hit }
        let url = try await supabase.storage.from(bucket).createSignedURL(path: path, expiresIn: 3600)
        let (data, _) = try await URLSession.shared.data(from: url)
        cache[path] = data
        return data
    }

    /// True when the iPhone's on-device check thinks the photo contains nudity.
    /// Only runs when the person (or Screen Time) has turned the check on.
    static func isSensitive(_ image: UIImage) async -> Bool {
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled, let cg = image.cgImage else { return false }
        return (try? await analyzer.analyzeImage(cg))?.isSensitive ?? false
    }
}

/// Records a voice note to a temporary .m4a file.
@MainActor
@Observable
final class VoiceRecorder {
    private(set) var recording = false
    private(set) var started: Date?
    private var recorder: AVAudioRecorder?
    private var file: URL?

    func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let r = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            r.record(forDuration: 120)
            recorder = r
            file = url
            started = .now
            recording = true
            Haptics.bump()
            return true
        } catch {
            return false
        }
    }

    /// Stops and returns the file and its length, or nil for a recording under a second.
    func finish() -> (url: URL, ms: Int)? {
        guard let recorder, let file else { return nil }
        let ms = Int(recorder.currentTime * 1000)
        recorder.stop()
        reset()
        return ms >= 1000 ? (file, ms) : nil
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        reset()
    }

    private func reset() {
        recorder = nil
        file = nil
        started = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Plays one voice note at a time.
@MainActor
@Observable
final class VoicePlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = VoicePlayer()
    private(set) var playingPath: String?
    private(set) var progress: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ path: String) async {
        if playingPath == path { stop(); return }
        stop()
        guard let data = try? await ChatMedia.data(path), let p = try? AVAudioPlayer(data: data) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        p.delegate = self
        p.play()
        player = p
        playingPath = path
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player, p.duration > 0 else { return }
                self.progress = p.currentTime / p.duration
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        playingPath = nil
        progress = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
