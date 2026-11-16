import Foundation
import HallwayCore

/// Player choices, the saved run and records, kept on the phone.
@MainActor
final class GameSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    /// The game's language: menus, the Host, the creatures' voices.
    @Published var language: Language {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            if host.language != language { host = Host.all(language)[0] }
        }
    }
    @Published var languageChosen: Bool { didSet { defaults.set(languageChosen, forKey: "languageChosen") } }
    @Published var host: Host { didSet { defaults.set(host.rawValue, forKey: "host") } }
    @Published var hostChosen: Bool { didSet { defaults.set(hostChosen, forKey: "hostChosen") } }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    /// On-screen captions of sounds and of what the Host says.
    @Published var captions: Bool { didSet { defaults.set(captions, forKey: "captions") } }
    /// Off: the Host is spoken by the phone's own voice instead of the recordings.
    @Published var recordedHost: Bool { didSet { defaults.set(recordedHost, forKey: "recordedHost") } }
    @Published var musicVolume: Double { didSet { defaults.set(musicVolume, forKey: "musicVolume"); SoundBoard.shared.musicVolume = musicVolume } }
    @Published var ambienceVolume: Double { didSet { defaults.set(ambienceVolume, forKey: "ambienceVolume"); SoundBoard.shared.ambienceVolume = ambienceVolume } }
    @Published var effectsVolume: Double { didSet { defaults.set(effectsVolume, forKey: "effectsVolume"); SoundBoard.shared.effectsVolume = effectsVolume } }
    /// The Host explains the rules at the start (on until you've finished your first night).
    @Published var tutorial: Bool { didSet { defaults.set(tutorial, forKey: "tutorial") } }
    /// The Host has welcomed you to the Practice Room.
    @Published var practiceVisited: Bool { didSet { defaults.set(practiceVisited, forKey: "practiceVisited") } }

    @Published private(set) var savedRun: RunState?
    @Published private(set) var bestHour: Int
    @Published private(set) var nightsSurvived: Int
    @Published private(set) var nightsPlayed: Int

    init() {
        let phonePT = Locale.preferredLanguages.first?.hasPrefix("pt") ?? false
        let lang = Language(rawValue: defaults.string(forKey: "language") ?? "") ?? (phonePT ? .pt : .en)
        language = lang
        languageChosen = defaults.bool(forKey: "languageChosen")
        let saved = Host(rawValue: defaults.string(forKey: "host") ?? "")
        host = saved?.language == lang ? saved! : Host.all(lang)[0]
        // Players from the first version already chose their Host (in English).
        hostChosen = defaults.bool(forKey: "hostChosen")
        if hostChosen && !languageChosen { languageChosen = true }
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        captions = defaults.object(forKey: "captions") as? Bool ?? true
        recordedHost = defaults.object(forKey: "recordedHost") as? Bool ?? true
        musicVolume = defaults.object(forKey: "musicVolume") as? Double ?? 0.6
        ambienceVolume = defaults.object(forKey: "ambienceVolume") as? Double ?? 0.35
        effectsVolume = defaults.object(forKey: "effectsVolume") as? Double ?? 1.0
        tutorial = defaults.object(forKey: "tutorial") as? Bool ?? true
        practiceVisited = defaults.bool(forKey: "practiceVisited")
        bestHour = defaults.integer(forKey: "bestHour")
        nightsSurvived = defaults.integer(forKey: "nightsSurvived")
        nightsPlayed = defaults.integer(forKey: "nightsPlayed")
        if let data = defaults.data(forKey: "savedRun") {
            savedRun = try? JSONDecoder().decode(RunState.self, from: data)
        }
        let sound = SoundBoard.shared
        sound.musicVolume = musicVolume
        sound.ambienceVolume = ambienceVolume
        sound.effectsVolume = effectsVolume
    }

    /// Text in the player's language.
    func t(_ en: String, _ pt: String) -> String { language.t(en, pt) }

    func save(_ run: RunState) {
        savedRun = run
        if let data = try? JSONEncoder().encode(run) { defaults.set(data, forKey: "savedRun") }
    }

    func clearSavedRun() {
        savedRun = nil
        defaults.removeObject(forKey: "savedRun")
    }

    /// A night is over.
    func record(won: Bool, hour: Int) {
        clearSavedRun()
        nightsPlayed += 1
        defaults.set(nightsPlayed, forKey: "nightsPlayed")
        if won {
            nightsSurvived += 1
            defaults.set(nightsSurvived, forKey: "nightsSurvived")
            tutorial = false
        }
        let reached = won ? Game.hours : hour
        if reached > bestHour {
            bestHour = reached
            defaults.set(bestHour, forKey: "bestHour")
        }
        if nightsPlayed >= 2 { tutorial = false }
    }
}
