import HallwayCore
import SwiftUI
import UIKit

/// Runs a night: ticks the game 60 times a second, and turns its events into sound, the Host's voice,
/// vibration and what's on screen.
@MainActor
final class GameController: ObservableObject {
    @Published private(set) var phase: Phase = .busy
    @Published private(set) var run: RunState
    @Published private(set) var caption = ""
    /// What the Host is saying right now.
    @Published private(set) var hostText = ""
    @Published private(set) var talking = false
    @Published private(set) var creature: Creature?
    @Published private(set) var ended: Bool?
    @Published var paused = false

    let game: Game
    private let settings: GameSettings
    private let sound = SoundBoard.shared
    private let voice = HostVoice()
    private let haptics = Haptics()
    private var timer: Timer?
    private var last = Date()

    /// A night (new, or continued), or the Practice Room when `practice` is set.
    init(settings: GameSettings, resume: RunState?, practice: (creature: Creature, difficulty: Double)? = nil) {
        self.settings = settings
        if let practice {
            game = Game(host: settings.host, practice: practice.creature, difficulty: practice.difficulty,
                        seed: UInt64.random(in: 1...UInt64.max), welcome: !settings.practiceVisited)
        } else if let resume {
            game = Game(host: settings.host, resume: resume)
        } else {
            game = Game(host: settings.host, seed: UInt64.random(in: 1...UInt64.max), tutorial: settings.tutorial)
        }
        run = game.run
        sound.language = settings.language
        voice.host = settings.host
        voice.recorded = settings.recordedHost
        haptics.enabled = settings.haptics
        voice.onFinished = { [weak self] in
            guard let self else { return }
            self.talking = false
            self.sound.duck(false)
            self.game.hostFinished()
        }
    }

    func start() {
        guard timer == nil else { return }
        if game.practice != nil { settings.practiceVisited = true }
        UIApplication.shared.isIdleTimerDisabled = true
        last = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        voice.stop()
        sound.stopEffects()
        sound.ambience(nil)
        sound.music(.menu)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(last), 0.1)
        last = now
        guard !paused else { return }
        game.update(dt)
        handle(game.drainEvents())
        sync()
    }

    func input(_ input: Input) {
        guard !paused else { return }
        game.input(input)
        handle(game.drainEvents())
        sync()
    }

    func setPaused(_ p: Bool) {
        paused = p
        voice.pause(p)
        sound.pause(p)
        if !p { last = Date() }
    }

    private func sync() {
        if phase != game.phase { phase = game.phase }
        if run != game.run { run = game.run }
        let c = game.encounter?.creature
        if creature != c { creature = c }
    }

    private func handle(_ events: [GameEvent]) {
        for e in events {
            switch e {
            case let .say(id):
                hostText = HostScript.text(id, game.host)
                talking = true
                sound.duck(true)
                voice.say(id)
            case .stopSpeech:
                voice.stop()
                talking = false
                sound.duck(false)
            case let .play(cue):
                sound.play(cue)
            case let .ambience(a):
                sound.ambience(a)
            case let .music(t):
                sound.music(t)
            case let .haptic(h):
                haptics.play(h)
            case let .caption(text):
                caption = text
            case .save:
                if game.practice == nil { settings.save(game.run) }
            case let .ended(won):
                settings.record(won: won, hour: game.run.hour, survived: game.run.stats.survived)
                ended = won
            case let .achievement(id):
                settings.earn(id)
            }
        }
    }

    /// Leave in the middle of a night: it continues from the start of this hour (or the shop).
    func quit() {
        stop()
    }
}
