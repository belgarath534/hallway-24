/// A robot player for testing: it plays whole runs much faster than real time.
///
/// It "hears" by reading the game's state: the door hints, and what the creature wants. `skill` is the chance
/// it gets an encounter right, `ear` the chance it notices the Mimic's lower sound on a door, and `reaction`
/// how long it takes to respond (a person needs about half a second).
public struct BotPlayer: Sendable {
    public var skill: Double
    public var ear: Double
    public var reaction: Double
    var rng: RNG
    private enum Mistake { case none, late, early, touch }
    private var mistake = Mistake.none
    private var inEncounter = false
    private var touchAt = 0.0
    private var choseAt = -1
    private var idleFor = 0.0

    public init(skill: Double, ear: Double, reaction: Double, seed: UInt64) {
        self.skill = skill
        self.ear = ear
        self.reaction = reaction
        rng = RNG(seed: seed ^ 0xB07)
    }

    /// What the bot does right now, if anything.
    public mutating func act(_ game: Game) -> Input? {
        if game.phase != .encounter { inEncounter = false }
        idleFor = game.isIdle ? idleFor + 1.0 / 30 : 0
        switch game.phase {
        case .hallway:
            // Listens to everything, thinks for a moment, then picks.
            let room = game.run.hour * 10 + game.run.step
            guard game.run.doors.count == 2, choseAt != room, idleFor > 1.5 else { return nil }
            if game.run.health < 2, game.run.count(.bandage) > 0 { return .use(.bandage) }
            choseAt = room
            return chooseDoor(game.run.doors)
        case .encounter:
            guard let e = game.encounter else { return nil }
            if !inEncounter {
                inEncounter = true
                // Later creatures are faster and trickier: people make more mistakes.
                mistake = skill >= 1 || rng.chance(skill - 0.15 * e.difficulty) ? .none : rng.pick([.late, .early, .touch])
                touchAt = rng.range(1.5, 7)
            }
            switch mistake {
            case .late: return nil
            case .touch: return e.time >= touchAt && e.time < touchAt + 0.04 ? .tap : nil
            case .early:
                // Presses once, too soon.
                guard let need = e.nextRequired, e.time >= max(0.4, need.from - 0.7) else { return nil }
                mistake = .late
                return need.input
            case .none:
                guard let need = e.nextRequired else { return nil }
                return e.time >= need.from + reaction ? need.input : nil
            }
        case .shop:
            guard idleFor > 1 else { return nil }
            let r = game.run
            if r.tokens >= Item.charm.price, r.count(.charm) == 0 { return .buy(.charm) }
            if r.tokens >= Item.bandage.price, r.count(.bandage) == 0 { return .buy(.bandage) }
            if r.tokens >= Item.lighter.price, r.count(.lighter) == 0 { return .buy(.lighter) }
            return .leave
        case .busy, .won, .lost:
            return nil
        }
    }

    private mutating func chooseDoor(_ doors: [Door]) -> Input {
        func soundsSafe(_ d: Door) -> Bool {
            let safeHints = Set(SafeRoom.allCases.map(\.hint))
            guard safeHints.contains(d.hint) else { return false }
            return d.rate == 1 || !rng.chance(ear)
        }
        let left = soundsSafe(doors[0]), right = soundsSafe(doors[1])
        if left != right { return left ? .left : .right }
        return rng.chance(0.5) ? .left : .right
    }
}

public enum Simulator {
    public struct Result: Equatable, Sendable {
        public var won: Bool
        public var hour: Int
        public var health: Int
        public var seconds: Double
        public var lines: [String]
        public var stats: RunStats
    }

    /// Plays a run with the bot. `talk`: count the time the Host spends talking (an estimate), for run length.
    public static func play(seed: UInt64, host: Host = .lewis, bot: BotPlayer, talk: Bool = false,
                            resume: RunState? = nil, stopAtHour: Int? = nil) -> (Result, Game) {
        let game = resume.map { Game(host: host, resume: $0) } ?? Game(host: host, seed: seed, tutorial: true)
        var bot = bot
        let dt = 1.0 / 30
        var t = 0.0, speaking = 0.0
        var lines: [String] = []
        var ended: Bool?
        while ended == nil, t < 4 * 3600 {
            if game.waitingForHost {
                speaking -= dt
                if !talk || speaking <= 0 { game.hostFinished() }
            }
            if let stop = stopAtHour, game.run.hour >= stop, game.phase == .hallway { break }
            if let input = bot.act(game) { game.input(input) }
            game.update(dt)
            for e in game.drainEvents() {
                switch e {
                case let .say(id):
                    lines.append(id)
                    let words = HostScript.text(id, host).split(separator: " ").count
                    speaking = Double(words) / 2.6 + 0.3
                case let .ended(won):
                    ended = won
                default:
                    break
                }
            }
            t += dt
        }
        let r = Result(won: ended ?? false, hour: game.run.hour, health: game.run.health, seconds: t, lines: lines, stats: game.run.stats)
        return (r, game)
    }
}
