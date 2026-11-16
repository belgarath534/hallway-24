import AppIntents
import Foundation
import HallwayCore

/// Siri, Shortcuts, Spotlight and the Action button. These work in the player's language: the phrases
/// are translated in pt-BR.lproj/AppShortcuts.strings.
///
///   "Start a night in Hallway 24"             opens the game and starts (or continues) a night
///   "Open the practice room in Hallway 24"    opens the Practice Room
///   "What's my record in Hallway 24"          Siri answers out loud, without opening the game

/// What the app should open when Siri or a shortcut launches it.
@MainActor
final class AppLaunch: ObservableObject {
    static let shared = AppLaunch()
    enum Request { case night, practice }
    @Published var request: Request?
}

private var gameLanguage: Language {
    let saved = UserDefaults.standard.string(forKey: "language") ?? ""
    let phonePT = Locale.preferredLanguages.first?.hasPrefix("pt") ?? false
    return Language(rawValue: saved) ?? (phonePT ? .pt : .en)
}

struct StartNightIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Night"
    static var description = IntentDescription("Opens Hallway 24 and starts a night. If you saved a night, it continues that one.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppLaunch.shared.request = .night
        return .result()
    }
}

struct OpenPracticeIntent: AppIntent {
    static var title: LocalizedStringResource = "Open the Practice Room"
    static var description = IntentDescription("Opens the Practice Room, where you can practice any creature without losing hearts.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppLaunch.shared.request = .practice
        return .result()
    }
}

struct RecordIntent: AppIntent {
    static var title: LocalizedStringResource = "My Record"
    static var description = IntentDescription("Siri tells you how many nights you've survived and how far you've gotten.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let d = UserDefaults.standard
        let played = d.integer(forKey: "nightsPlayed"), won = d.integer(forKey: "nightsSurvived")
        let best = d.integer(forKey: "bestHour"), creatures = d.integer(forKey: "creaturesSurvived")
        let saved = d.data(forKey: "savedRun").flatMap { try? JSONDecoder().decode(RunState.self, from: $0) }
        let l = gameLanguage
        var text: String
        if played == 0 {
            text = l.t("You haven't finished a night yet. The hallway is waiting.",
                       "Você ainda não terminou nenhuma noite. O corredor está esperando.")
        } else {
            text = l.t("You've survived \(won) of \(played) \(played == 1 ? "night" : "nights"). Your furthest is hour \(best), and you've gotten past \(creatures) \(creatures == 1 ? "creature" : "creatures").",
                       "Você sobreviveu a \(won) de \(played) \(played == 1 ? "noite" : "noites"). O mais longe foi a hora \(best), e você passou por \(creatures) \(creatures == 1 ? "criatura" : "criaturas").")
        }
        if let saved {
            text += " " + l.t("You have a saved night at hour \(saved.hour), with \(saved.health) \(saved.health == 1 ? "heart" : "hearts") left.",
                              "Você tem uma noite salva na hora \(saved.hour), com \(saved.health) \(saved.health == 1 ? "coração" : "corações").")
        }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct HallwayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartNightIntent(), phrases: [
            "Start a night in \(.applicationName)",
            "Play \(.applicationName)",
            "Continue my night in \(.applicationName)",
        ], shortTitle: "Start a Night", systemImageName: "door.left.hand.open")
        AppShortcut(intent: OpenPracticeIntent(), phrases: [
            "Open the practice room in \(.applicationName)",
            "Practice in \(.applicationName)",
        ], shortTitle: "Practice Room", systemImageName: "figure.run")
        AppShortcut(intent: RecordIntent(), phrases: [
            "What's my record in \(.applicationName)",
            "How many nights have I survived in \(.applicationName)",
        ], shortTitle: "My Record", systemImageName: "trophy")
    }
}
