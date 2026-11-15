import AVFoundation
import HallwayCore

/// The Host's voice: plays the recording of a line (v_<host>_<id>.m4a), or speaks the text with the
/// phone's own voice if there's no recording or recordings are off. One line at a time.
@MainActor
final class HostVoice: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    var host: Host = .lewis
    var recorded = true
    /// Called when a line finishes on its own (not when it's stopped).
    var onFinished: (() -> Void)?

    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?

    override init() {
        super.init()
        synth.delegate = self
    }

    static func url(_ id: String, _ host: Host) -> URL? {
        let name = "v_\(host.rawValue)_\(id)"
        return Bundle.main.url(forResource: name, withExtension: "m4a")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Voices")
    }

    func say(_ id: String) {
        stop()
        if recorded, let url = Self.url(id, host), let p = try? AVAudioPlayer(contentsOf: url) {
            p.delegate = self
            p.play()
            player = p
            return
        }
        let u = AVSpeechUtterance(string: HostScript.text(id, host))
        u.voice = AVSpeechSynthesisVoice(language: host == .lewis ? "en-GB" : "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * (host == .lewis ? 0.95 : 1.02)
        u.pitchMultiplier = host == .lewis ? 0.9 : 1.15
        utterance = u
        synth.speak(u)
    }

    func stop() {
        player?.delegate = nil
        player?.stop()
        player = nil
        utterance = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    func pause(_ paused: Bool) {
        if paused {
            player?.pause()
            synth.pauseSpeaking(at: .word)
        } else {
            player?.play()
            synth.continueSpeaking()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(p)
        Task { @MainActor in
            guard let player = self.player, ObjectIdentifier(player) == id else { return }
            self.player = nil
            self.onFinished?()
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in
            guard let utterance = self.utterance, ObjectIdentifier(utterance) == id else { return }
            self.utterance = nil
            self.onFinished?()
        }
    }
}
