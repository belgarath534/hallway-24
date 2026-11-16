import AVFoundation
import HallwayCore

/// All of the game's sound except the Host: effects placed left or right, sounds heard through a door
/// (quieter and dull), background loops and music.
///
/// Effects run through a small pool of voices: player → varispeed (the Mimic's lower voice) → low-pass
/// filter (through a door) → mixer (left/right and volume).
///
/// With headphones and 3D sound on, each voice's mixer feeds a 3D space (AVAudioEnvironmentNode) instead:
/// sounds come from a real direction, in front of you or behind you, and on iOS 18 with AirPods that
/// support head tracking, they stay in place when you turn your head. Without headphones it's plain
/// left/right, so the game always plays the same.
@MainActor
final class SoundBoard {
    static let shared = SoundBoard()

    private struct Voice {
        let player = AVAudioPlayerNode()
        let speed = AVAudioUnitVarispeed()
        let filter = AVAudioUnitEQ(numberOfBands: 1)
        let mixer = AVAudioMixerNode()
    }

    private let engine = AVAudioEngine()
    private let space = AVAudioEnvironmentNode()
    /// The player's choice (Settings). Only used while headphones are connected.
    var spatialWanted = true { didSet { route() } }
    /// Sounds are in 3D right now.
    private(set) var spatialOn = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var voices: [Voice] = []
    private var nextVoice = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private let ambiencePlayer = AVAudioPlayerNode()
    private let ambienceMixer = AVAudioMixerNode()
    private var currentAmbience: Ambience?
    private var music: AVAudioPlayer?
    private var currentTrack: Track?
    private var ducked = false
    var musicVolume: Double = 0.6 { didSet { music?.volume = targetMusicVolume } }
    /// Background loops. Kept low by default so the Host and the creatures are easy to hear.
    var ambienceVolume: Double = 0.35 { didSet { ambienceMixer.outputVolume = targetAmbienceVolume } }
    var effectsVolume: Double = 1.0
    /// Spoken sounds (the Counter, the Mimic) use this language.
    var language: Language = .en

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        for _ in 0..<12 {
            let v = Voice()
            let band = v.filter.bands[0]
            band.filterType = .lowPass
            band.frequency = 900
            band.bypass = false
            v.filter.bypass = true
            for node in [v.player, v.speed, v.filter, v.mixer] as [AVAudioNode] { engine.attach(node) }
            engine.connect(v.player, to: v.speed, format: format)
            engine.connect(v.speed, to: v.filter, format: format)
            engine.connect(v.filter, to: v.mixer, format: format)
            engine.connect(v.mixer, to: engine.mainMixerNode, format: format)
            voices.append(v)
        }
        engine.attach(space)
        engine.connect(space, to: engine.mainMixerNode, format: nil)
        space.renderingAlgorithm = .auto
        space.reverbParameters.enable = false
        // No quieter with distance up close: the game sets volumes itself.
        space.distanceAttenuationParameters.referenceDistance = 3
        space.distanceAttenuationParameters.maximumDistance = 20
        space.distanceAttenuationParameters.rolloffFactor = 0.6
        engine.attach(ambiencePlayer)
        engine.attach(ambienceMixer)
        engine.connect(ambiencePlayer, to: ambienceMixer, format: format)
        engine.connect(ambienceMixer, to: engine.mainMixerNode, format: format)
        load()
        route()
        start()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.route() }
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.ended.rawValue {
                MainActor.assumeIsolated {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self?.start()
                    self?.music?.play()
                }
            }
        }
    }

    /// Headphones of any kind: wired, Bluetooth (AirPods), USB.
    private static var headphonesConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains {
            [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio].contains($0.portType)
        }
    }

    /// Sends the effects to the 3D space (headphones and 3D sound on) or straight to the speakers.
    private func route() {
        let spatial = spatialWanted && Self.headphonesConnected
        if #available(iOS 18.0, *) {
            space.isListenerHeadTrackingEnabled = spatial
        }
        guard spatial != spatialOn || !routed else { return }
        routed = true
        spatialOn = spatial
        let wasRunning = engine.isRunning
        if wasRunning {
            stopEffects()
            engine.stop()
        }
        for v in voices {
            engine.disconnectNodeOutput(v.mixer)
            if spatial {
                engine.connect(v.mixer, to: space, format: format)
                v.mixer.renderingAlgorithm = .auto
                v.mixer.sourceMode = .spatializeIfMono
                v.mixer.reverbBlend = 0
            } else {
                engine.connect(v.mixer, to: engine.mainMixerNode, format: format)
            }
        }
        if wasRunning { start() }
    }
    private var routed = false

    /// Where a sound is in the 3D space: the game's left/right as an angle, in front of you or behind you.
    /// Through a door is a little further away.
    private static func position(_ cue: SoundCue) -> AVAudio3DPoint {
        let angle = max(-1, min(1, cue.pan)) * Double.pi / 2
        let distance = cue.muffled ? 2.5 : 1.0
        let x = sin(angle) * distance
        let z = cos(angle) * distance * (cue.behind ? 1 : -1)   // the listener faces −z
        return AVAudio3DPoint(x: Float(x), y: 0, z: Float(z))
    }

    private func start() {
        guard !engine.isRunning else { return }
        try? engine.start()
        if let amb = currentAmbience {
            currentAmbience = nil
            ambience(amb)
        }
    }

    private func load() {
        let names = Sfx.allCases.map { "sfx_\($0.rawValue)" } + Sfx.allCases.filter(\.spoken).map { "sfx_pt_\($0.rawValue)" }
            + Ambience.allCases.map(\.rawValue)
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "m4a")
                ?? Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Sounds"),
                  let file = try? AVAudioFile(forReading: url),
                  let buffer = Self.read(file, as: format) else { continue }
            buffers[name] = buffer
        }
    }

    /// Reads a whole file as mono 44.1 kHz, converting if it isn't already.
    private static func read(_ file: AVAudioFile, as format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              (try? file.read(into: raw)) != nil else { return nil }
        if raw.format == format { return raw }
        guard let converter = AVAudioConverter(from: raw.format, to: format) else { return nil }
        let capacity = AVAudioFrameCount(Double(frames) * format.sampleRate / raw.format.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return raw
        }
        return error == nil ? out : nil
    }

    // MARK: Effects

    func play(_ cue: SoundCue) {
        start()
        let name = cue.sfx.spoken && language == .pt ? "sfx_pt_\(cue.sfx.rawValue)" : "sfx_\(cue.sfx.rawValue)"
        guard let buffer = buffers[name] ?? buffers["sfx_\(cue.sfx.rawValue)"] else { return }
        let v = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        v.player.stop()
        v.speed.rate = Float(cue.rate)
        v.filter.bypass = !cue.muffled
        if spatialOn {
            v.mixer.position = Self.position(cue)
        } else {
            v.mixer.pan = Float(max(-1, min(1, cue.pan)))
        }
        v.mixer.outputVolume = Float(cue.volume * effectsVolume)
        v.player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        v.player.play()
    }

    /// Settings: a knock walks in a circle around your head, starting in front of you, then stays
    /// in front so you can turn your head and hear it stay put.
    func testSpatial() {
        let path: [(Double, Bool)] = [(0, false), (0.5, false), (1, false), (0.5, true), (0, true), (-0.5, true), (-1, false), (-0.5, false)]
        Task { @MainActor in
            for (pan, behind) in path + Array(repeating: (0, false), count: 8) {
                play(SoundCue(.neighborKnock, pan: pan, volume: 0.8, behind: behind))
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    func stopEffects() {
        for v in voices { v.player.stop() }
    }

    // MARK: Ambience

    func ambience(_ amb: Ambience?) {
        guard amb != currentAmbience else { return }
        currentAmbience = amb
        ambiencePlayer.stop()
        guard let amb, let buffer = buffers[amb.rawValue] else { return }
        start()
        ambienceMixer.outputVolume = targetAmbienceVolume
        ambiencePlayer.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        ambiencePlayer.play()
    }

    // MARK: Music

    private var targetMusicVolume: Float { Float(musicVolume * (ducked ? 0.35 : 1) * 0.7) }

    /// The ambience recordings are loud: even at 100% the slider keeps them well under the Host.
    private var targetAmbienceVolume: Float {
        Float(ambienceVolume * (ducked ? 0.4 : 1) * (currentAmbience == .deep ? 0.5 : 0.4))
    }

    func music(_ track: Track?) {
        guard track != currentTrack else { return }
        currentTrack = track
        let old = music
        old?.setVolume(0, fadeDuration: 1.2)
        if let old {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                old.stop()
            }
        }
        music = nil
        guard let track,
              let url = Bundle.main.url(forResource: track.rawValue, withExtension: "m4a")
                ?? Bundle.main.url(forResource: track.rawValue, withExtension: "m4a", subdirectory: "Music"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = (track == .win || track == .lose) ? 0 : -1
        player.volume = 0
        player.play()
        player.setVolume(targetMusicVolume, fadeDuration: 1.5)
        music = player
    }

    /// Quieter music while the Host talks.
    func duck(_ on: Bool) {
        guard on != ducked else { return }
        ducked = on
        music?.setVolume(targetMusicVolume, fadeDuration: 0.4)
        ambienceMixer.outputVolume = targetAmbienceVolume
    }

    func pause(_ paused: Bool) {
        if paused {
            music?.pause()
            ambiencePlayer.pause()
            stopEffects()
        } else {
            music?.play()
            if currentAmbience != nil { ambiencePlayer.play() }
        }
    }
}
