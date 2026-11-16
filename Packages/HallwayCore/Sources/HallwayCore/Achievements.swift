/// The Game Center achievements and leaderboards. The game sends `.achievement(id)` events;
/// the app keeps them and reports them to Game Center as "hallway24.<id>".
/// store/game_center/achievements.json has the same list for setting them up in App Store Connect.
public struct Achievement: Sendable {
    public let id: String
    public let title: (en: String, pt: String)
    public let detail: (en: String, pt: String)
    public let points: Int

    public var gameCenterID: String { "hallway24.\(id)" }

    public static let all: [Achievement] = [
        a("first_door", ("The First Door", "A Primeira Porta"), ("Open your first door.", "Abra sua primeira porta."), 5),
        a("survive_drip", ("Hid in Time", "Escondido a Tempo"), ("Survive the Drip.", "Sobreviva à Goteira."), 15),
        a("survive_static", ("Grounded", "Aterrado"), ("Survive Static.", "Sobreviva à Estática."), 15),
        a("survive_crawler", ("Run or Freeze", "Corre ou Congela"), ("Survive the Crawler.", "Sobreviva ao Rastejante."), 15),
        a("survive_counter", ("Statue", "Estátua"), ("Survive the Counter.", "Sobreviva ao Contador."), 20),
        a("survive_mimic", ("Not Fooled", "Não Me Engana"), ("Find the real voice and survive the Mimic.", "Ache a voz real e sobreviva ao Imitador."), 20),
        a("solve_echo", ("Music Box", "Caixinha de Música"), ("Solve the Echo's puzzle.", "Resolva o enigma do Eco."), 20),
        a("lighter", ("Peeking", "Espiando"), ("Use the lighter to look under the doors.", "Use o isqueiro para espiar embaixo das portas."), 10),
        a("shopper", ("Good Customer", "Bom Cliente"), ("Buy something in the Host's shop.", "Compre algo na loja do apresentador."), 10),
        a("second_chance", ("Not Yet", "Ainda Não"), ("Get saved by a Second Chance.", "Seja salvo por uma Segunda Chance."), 20),
        a("practice", ("Rehearsal", "Ensaio"), ("Survive a challenge in the Practice Room.", "Vença um desafio na Sala de Treino."), 10),
        a("hour_12", ("Halfway", "Metade do Caminho"), ("Reach hour twelve.", "Chegue à hora doze."), 30),
        a("first_night", ("Dawn", "Amanhecer"), ("Survive the whole night.", "Sobreviva à noite inteira."), 100),
        a("last_heart", ("By a Thread", "Por um Fio"), ("Survive the night with one heart left.", "Sobreviva à noite com um coração só."), 50),
        a("untouchable", ("Untouchable", "Intocável"), ("Survive the night without getting caught once.", "Sobreviva à noite sem ser pego nenhuma vez."), 100),
        a("nights_5", ("Regular Guest", "Hóspede Fiel"), ("Survive five nights.", "Sobreviva a cinco noites."), 100),
    ]

    private static func a(_ id: String, _ t: (String, String), _ d: (String, String), _ p: Int) -> Achievement {
        Achievement(id: id, title: (t.0, t.1), detail: (d.0, d.1), points: p)
    }

    public static func named(_ id: String) -> Achievement? { all.first { $0.id == id } }
}

public enum Leaderboard: String, CaseIterable, Sendable {
    case furthestHour = "hallway24.furthest_hour"
    case nightsSurvived = "hallway24.nights_survived"
    case creaturesSurvived = "hallway24.creatures_survived"
}
