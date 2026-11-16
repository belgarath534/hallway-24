/// Something the app should do: play a sound, let the Host speak, vibrate, save…
public enum GameEvent: Equatable, Sendable {
    /// The Host says a line (by id, see HostScript). The game waits until the app calls `hostFinished()`.
    case say(String)
    /// Stop the Host mid-sentence (the player skipped, or made a choice).
    case stopSpeech
    case play(SoundCue)
    case ambience(Ambience?)
    case music(Track?)
    case haptic(Haptic)
    /// A short on-screen caption of what's happening (for sighted and deaf players).
    case caption(String)
    /// A good moment to save the run (start of an hour, doors ready).
    case save
    /// The run is over. Show the results.
    case ended(won: Bool)
    /// A Game Center achievement was earned (its id, see Achievements.swift).
    case achievement(String)
    /// The player has practiced this creature: no practice rounds for it next time (the app remembers).
    case learned(Creature)
}

public enum Phase: String, Codable, Sendable {
    /// Something is happening; wait (the Host may be talking).
    case busy
    /// Two doors: choose left or right, listen again, or use an item.
    case hallway
    /// A creature. Touches go straight to the game.
    case encounter
    /// The Host's shop.
    case shop
    case won, lost
    /// Practice Room: the challenge is over. Try again or leave.
    case practiceOver
}

public struct RunStats: Codable, Equatable, Sendable {
    public var survived = 0
    public var hits = 0
    public var safeRooms = 0
    public var tokensEarned = 0
}

/// Everything needed to continue a run later.
public struct RunState: Codable, Equatable, Sendable {
    public var rng: RNG
    public var hour = 1
    /// Which door of this hour, 1 to Game.roomsPerHour.
    public var step = 1
    public var health = Game.maxHealth
    public var tokens = 0
    /// Item raw value → how many.
    public var items: [String: Int] = [Item.lighter.rawValue: 1]
    /// This hour's doors, left then right.
    public var doors: [Door] = []
    /// Creatures you've met (the Host explains each one fully the first time).
    public var met: [Creature] = []
    public var stats = RunStats()
    /// Saved while in the Host's shop (continue there).
    public var atShop = false
    /// Doors left with double tokens (the Lucky Coin).
    public var coinDoors = 0

    public init(seed: UInt64) { rng = RNG(seed: seed) }

    enum CodingKeys: String, CodingKey { case rng, hour, step, health, tokens, items, doors, met, stats, atShop, coinDoors }

    /// Saves from older versions are missing newer fields: those start at their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rng = try c.decode(RNG.self, forKey: .rng)
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 1
        step = try c.decodeIfPresent(Int.self, forKey: .step) ?? 1
        health = try c.decodeIfPresent(Int.self, forKey: .health) ?? Game.maxHealth
        tokens = try c.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
        items = try c.decodeIfPresent([String: Int].self, forKey: .items) ?? [:]
        doors = try c.decodeIfPresent([Door].self, forKey: .doors) ?? []
        met = (try? c.decodeIfPresent([Creature].self, forKey: .met)) ?? []
        stats = try c.decodeIfPresent(RunStats.self, forKey: .stats) ?? RunStats()
        atShop = try c.decodeIfPresent(Bool.self, forKey: .atShop) ?? false
        coinDoors = try c.decodeIfPresent(Int.self, forKey: .coinDoors) ?? 0
    }

    public func count(_ item: Item) -> Int { items[item.rawValue] ?? 0 }
}

/// The game: a state machine the app drives with `update(dt)` and `input(_:)`, and that answers with events.
/// No sound, screen or clock of its own, so it runs the same on a phone, in tests and in the test bot.
public final class Game {
    public static let maxHealth = 3
    public static let hours = 24
    public static let shopHours: Set<Int> = [6, 12, 18]
    /// Doors per hour.
    public static let roomsPerHour = 3

    enum Step: Sendable { case showDoors, shop, practiceOver, enter(Room), encounter(Creature), finishRoom, nextHour, win, lose }

    enum Beat: Sendable {
        case say(String)
        case wait(Double)
        case event(GameEvent)
        case step(Step)
    }

    public let host: Host
    public var language: Language { host.language }
    public private(set) var run: RunState
    /// Practice Room: which challenge, at what difficulty. Nothing counts.
    public let practice: Creature?
    private var practiceDifficulty = 0.0
    /// Creatures the player has already practiced (in any night). The first time one shows up,
    /// there are up to three practice rounds before the real one.
    public private(set) var learned: Set<Creature>
    /// The creature being practiced right now, and how many practice rounds so far.
    public private(set) var training: Creature?
    private var trainingTries = 0
    public static let practiceRounds = 3
    public private(set) var phase: Phase = .busy
    public private(set) var encounter: Encounter?
    public private(set) var waitingForHost = false
    /// The line the Host is saying right now.
    public private(set) var currentLine: String?
    /// The room you're in (after choosing a door).
    public private(set) var room: Room?
    private var beats: [Beat] = []
    private var pause = 0.0
    private var events: [GameEvent] = []

    /// A new run. `tutorial`: the Host explains the rules first.
    public init(host: Host, seed: UInt64, tutorial: Bool, learned: Set<Creature> = []) {
        self.host = host
        self.learned = learned
        practice = nil
        run = RunState(seed: seed)
        beats = tutorial
            ? [.event(.music(.early)), .event(.ambience(.hallway)), .say("intro_1"), .say("intro_2"), .say("intro_3"), .say("intro_4"), .step(.showDoors)]
            : [.event(.music(.early)), .event(.ambience(.hallway)), .say("new_run"), .step(.showDoors)]
    }

    /// Continues a saved run at the start of its hour.
    public init(host: Host, resume: RunState, learned: Set<Creature> = []) {
        self.host = host
        self.learned = learned
        practice = nil
        run = resume
        beats = [.event(.music(Self.track(for: resume.hour))), .say("welcome_back"), .step(resume.atShop ? .shop : .showDoors)]
    }

    /// The Practice Room: one challenge, as many times as you like, and nothing hurts.
    public init(host: Host, practice c: Creature, difficulty: Double, seed: UInt64, welcome: Bool) {
        self.host = host
        learned = Set(Creature.allCases)
        practice = c
        practiceDifficulty = difficulty
        run = RunState(seed: seed)
        run.met = Creature.allCases
        beats = (welcome ? [.say("practice_welcome")] : []) + [.say("learn_\(c.rawValue)"), .step(.enter(.creature(c)))]
    }

    /// Nothing is playing or being said: the player has heard everything.
    public var isIdle: Bool { beats.isEmpty && !waitingForHost && pause <= 0 }

    /// 0 at the first door, 1 at the very last one.
    public var difficulty: Double {
        if practice != nil { return practiceDifficulty }
        return Double((run.hour - 1) * Self.roomsPerHour + run.step - 1) / Double(Self.hours * Self.roomsPerHour - 1)
    }

    /// Events since the last call, in order.
    public func drainEvents() -> [GameEvent] {
        defer { events.removeAll() }
        return events
    }

    /// The app calls this when the Host's line has finished playing.
    public func hostFinished() {
        waitingForHost = false
        currentLine = nil
    }

    public func update(_ dt: Double) {
        if phase == .encounter, var e = encounter {
            events += e.update(dt)
            encounter = e
            if let outcome = e.outcome { finishEncounter(outcome) }
        }
        runBeats(dt)
    }

    public func input(_ input: Input) {
        if input == .skip {
            skipLine()
            return
        }
        switch phase {
        case .encounter:
            guard var e = encounter else { return }
            events += e.input(input)
            encounter = e
            if let outcome = e.outcome { finishEncounter(outcome) }
        case .hallway:
            switch input {
            case .left: choose(.left)
            case .right: choose(.right)
            case .tap: if waitingForHost { skipLine() } else { listen() }
            case .listen: listen()
            case let .use(item): use(item)
            default: break
            }
        case .shop:
            switch input {
            case let .buy(item): buy(item)
            case .leave: leaveShop()
            case .tap: skipLine()
            default: break
            }
        case .busy:
            if input == .tap { skipLine() }
        case .practiceOver:
            if input == .again, let c = practice {
                interrupt()
                beats = [.say("meet_\(c.rawValue)"), .step(.enter(.creature(c)))]
                phase = .busy
            } else if input == .tap {
                skipLine()
            }
        case .won, .lost:
            break
        }
    }

    // MARK: Beats

    private func runBeats(_ dt: Double) {
        if pause > 0 {
            pause -= dt
            if pause > 0 { return }
            pause = 0
        }
        while !waitingForHost, pause <= 0, !beats.isEmpty {
            switch beats.removeFirst() {
            case let .say(id):
                events.append(.say(id))
                currentLine = id
                waitingForHost = true
            case let .wait(seconds):
                pause = seconds
            case let .event(e):
                events.append(e)
            case let .step(step):
                perform(step)
            }
        }
    }

    private func skipLine() {
        guard waitingForHost else { return }
        events.append(.stopSpeech)
        hostFinished()
    }

    /// Stops whatever is going on (talk, hints) so something new can start right away.
    private func interrupt() {
        if waitingForHost {
            events.append(.stopSpeech)
            hostFinished()
        }
        beats.removeAll()
        pause = 0
    }

    private func perform(_ step: Step) {
        switch step {
        case .showDoors: showDoors()
        case .shop: openShop()
        case .practiceOver: phase = .practiceOver
        case let .enter(room): enter(room)
        case let .encounter(c): startEncounter(c)
        case .finishRoom: finishRoom()
        case .nextHour:
            run.hour += 1
            run.step = 1
            showDoors()
        case .win: end(won: true)
        case .lose: end(won: false)
        }
    }

    private func variant(_ prefix: String) -> String { run.rng.pick(HostScript.variants(prefix)) }

    // MARK: The hallway

    static func track(for hour: Int) -> Track { hour <= 8 ? .early : hour <= 16 ? .middle : .late }

    private func showDoors() {
        if run.doors.count != 2 { run.doors = makeDoors() }
        room = nil
        phase = .hallway
        events.append(.save)
        let h = run.hour
        var b: [Beat] = [.event(.music(Self.track(for: h))), .event(.ambience(h >= 17 ? .deep : .hallway))]
        if run.step == 1 { b.append(.say("hour_\(h)")) }
        if h >= 12 { events.append(.achievement("hour_12")) }
        if h >= 16, run.rng.chance(0.12) {
            b.append(.say(variant("late")))
        } else if h >= 2, run.rng.chance(0.1) {
            b.append(.say(variant("tease")))
        }
        b.append(.say(h == 1 ? "doors_help" : variant("doors")))
        beats += b + hintBeats()
    }

    private func hintBeats() -> [Beat] {
        let quiet = 0.75 - 0.25 * difficulty
        var b: [Beat] = []
        for (i, side) in [Side.left, .right].enumerated() {
            let door = run.doors[i]
            b.append(.event(.caption(side == .left ? language.t("Left door…", "Porta da esquerda…") : language.t("Right door…", "Porta da direita…"))))
            b.append(.event(.play(SoundCue(door.hint, pan: side.pan, volume: quiet, rate: door.rate, muffled: true))))
            b.append(.wait(2.0))
        }
        return b
    }

    private func listen() {
        interrupt()
        beats = hintBeats()
    }

    private func use(_ item: Item) {
        interrupt()
        guard run.count(item) > 0 else {
            beats = [.say("\(item == .coin ? "coin" : item == .key ? "key" : item.rawValue)_none")]
            return
        }
        switch item {
        case .lighter:
            take(.lighter)
            events.append(.achievement("lighter"))
            beats = [.say("lighter_left"), .say("see_\(run.doors[0].room.key)"), .say("lighter_right"), .say("see_\(run.doors[1].room.key)")]
        case .bandage:
            guard run.health < Self.maxHealth else {
                beats = [.say("bandage_full")]
                return
            }
            take(.bandage)
            run.health += 1
            beats = [.event(.play(SoundCue(.heal))), .event(.haptic(.success)), .say("bandage_used")]
        case .coin:
            take(.coin)
            run.coinDoors += 9
            beats = [.event(.play(SoundCue(.coins))), .say("coin_used")]
        case .key:
            take(.key)
            run.doors = []
            phase = .busy
            beats = [.event(.play(SoundCue(.doorOpen))), .say("key_used"), .step(.finishRoom)]
        default:
            break
        }
    }

    private func take(_ item: Item) { run.items[item.rawValue, default: 0] -= 1 }

    private func give(_ item: Item) { run.items[item.rawValue, default: 0] += 1 }

    /// Tokens found; doubled while the Lucky Coin works.
    private func earn(_ n: Int) -> Int {
        let total = run.coinDoors > 0 ? n * 2 : n
        run.tokens += total
        run.stats.tokensEarned += total
        return total
    }

    private func tokenLine(_ n: Int) -> String { "tokens_\(min(max(n, 1), 12))" }

    private func choose(_ side: Side) {
        guard run.doors.count == 2 else { return }
        interrupt()
        let door = run.doors[side == .left ? 0 : 1]
        run.doors = []
        phase = .busy
        events.append(.achievement("first_door"))
        var b: [Beat] = []
        if run.rng.chance(0.35) { b.append(.say(variant("open"))) }
        b += [.event(.play(SoundCue(.doorOpen, pan: side.pan * 0.6))), .event(.haptic(.light)), .wait(1.0), .step(.enter(door.room))]
        beats = b
    }

    func makeDoors() -> [Door] {
        let d = difficulty
        let creatures = Creature.monsters.filter { $0.firstHour <= run.hour }.map { ($0, $0 == .mimic ? 1 + d : 1.0) }
        func creatureDoor() -> Door {
            let c = run.rng.weighted(creatures)
            if c == .mimic {
                let disguise = run.rng.pick(SafeRoom.allCases)
                return Door(room: .creature(.mimic), hint: disguise.hint, rate: 0.80 + 0.1 * d)
            }
            return Door(room: .creature(c), hint: c.hint)
        }
        func safeDoor() -> Door {
            let r = run.rng.weighted([(SafeRoom.bedroom, run.health < Self.maxHealth ? 0.4 : 0.15), (.kitchen, 0.3),
                                      (.vault, 1.1), (.storage, 0.7), (.empty, 2.0)])
            return Door(room: .safe(r), hint: r.hint)
        }
        let p = 0.6 + 0.3 * d
        var doors = [run.rng.chance(p) ? creatureDoor() : safeDoor(), run.rng.chance(p) ? creatureDoor() : safeDoor()]
        // Early on, one door is always safe. Later in the night, often neither is.
        if !doors[0].room.isSafe, !doors[1].room.isSafe, run.hour <= 2 || !run.rng.chance(0.5 + 0.4 * d) {
            doors[run.rng.int(0, 1)] = safeDoor()
        }
        // Sometimes a good room is swapped for the Echo's music box: a risk, but it pays well.
        if run.hour >= Creature.echo.firstHour, run.rng.chance(0.14), let i = doors.firstIndex(where: { $0.room.isSafe }) {
            doors[i] = Door(room: .creature(.echo), hint: .hintEcho)
        }
        // Later on, a good room is sometimes the Sleeper's: a sneaking puzzle that pays even better.
        if run.hour >= Creature.sleeper.firstHour, run.rng.chance(0.08),
           let i = doors.firstIndex(where: { $0.room.isSafe }) {
            doors[i] = Door(room: .creature(.sleeper), hint: .hintSleeper)
        }
        return doors
    }

    // MARK: Rooms

    private func enter(_ room: Room) {
        self.room = room
        switch room {
        case let .safe(kind):
            run.stats.safeRooms += 1
            var b: [Beat] = [.event(.ambience(.room)), .event(.caption(kind.name(language)))]
            switch kind {
            case .bedroom:
                if run.health < Self.maxHealth {
                    run.health += 1
                    b += [.event(.play(SoundCue(.heal))), .event(.haptic(.success)), .say(run.rng.pick(["room_bedroom_1", "room_bedroom_2"]))]
                } else {
                    b += [.say("room_bedroom_full")]
                }
            case .kitchen:
                run.items[Item.bandage.rawValue, default: 0] += 1
                b += [.event(.play(SoundCue(.itemGet))), .say(variant("room_kitchen"))]
            case .vault:
                let n = earn(run.rng.weighted([(2, 2.0), (3, 1.5), (4, 0.6)]))
                b += [.event(.play(SoundCue(.coins))), .say(variant("room_vault")), .say(tokenLine(n))]
            case .storage:
                let item = run.rng.weighted([(Item.lighter, 3.0), (.bandage, 1.0), (.earplugs, 0.8), (.coin, 0.6), (.key, 0.5), (.charm, 0.4)])
                give(item)
                b += [.event(.play(SoundCue(.itemGet))), .say(variant("room_storage")), .say("found_\(item.rawValue)")]
            case .empty:
                b += [.event(.play(SoundCue(.nothing))), .say(variant("room_empty"))]
            }
            beats += b + [.wait(0.6), .step(.finishRoom)]
        case .creature(.counter) where practice == nil && run.count(.earplugs) > 0:
            // Earplugs: you can't hear it count, so it can't trick you.
            take(.earplugs)
            if !run.met.contains(.counter) { run.met.append(.counter) }
            run.stats.survived += 1
            beats += [.event(.caption(Creature.counter.name(language))), .say("earplugs_used"), .wait(0.4), .step(.finishRoom)]
        case let .creature(c):
            let first = !run.met.contains(c)
            if first { run.met.append(c) }
            let needsPractice = practice == nil && !learned.contains(c)
            var b: [Beat] = [.event(.music(nil)), .event(.ambience(nil)), .event(.caption(c.name(language)))]
            if practice == nil {
                b += [.event(.play(SoundCue(c == .echo ? .hintEcho : .heartbeat))), .event(.haptic(.heartbeat))]
                if run.health == 1, !needsPractice, run.rng.chance(0.7) { b.append(.say(variant("last_heart"))) }
                b.append(.say(first || needsPractice ? "learn_\(c.rawValue)" : "meet_\(c.rawValue)"))
            }
            if needsPractice {
                if c == .echo {
                    // The Echo's lesson: each note once, with its name.
                    b.append(.say("echo_lesson"))
                    var t = 0.0
                    for (time, e) in Encounter.lesson() {
                        b += [.wait(time - t), .event(e)]
                        t = time
                    }
                    b.append(.wait(1.2))
                }
                training = c
                trainingTries = 0
                b.append(.say("training_intro"))
                beats += b + nextRound(c)
            } else {
                beats += b + nextRound(c)
            }
        }
    }

    /// The encounter that starts after the Host has explained it.
    private var pending: Encounter?

    /// Sets up the next encounter with this creature (a practice round while `training` is set) and starts it.
    private func nextRound(_ c: Creature) -> [Beat] {
        let practicing = training != nil || practice != nil
        // Practice rounds are a little easier than the real thing at this hour.
        let d = training != nil ? difficulty * 0.6 : difficulty
        pending = Encounter(creature: c, difficulty: d, rng: RNG(seed: run.rng.next()), language: language, guided: practicing)
        var b: [Beat] = []
        if c == .staticBuzz, let n = pending?.rounds { b.append(.say("static_\(n)")) }
        return b + [.wait(0.3), .step(.encounter(c))]
    }

    private func finishPractice(_ c: Creature, _ outcome: Encounter.Outcome) {
        var b: [Beat] = []
        switch outcome {
        case .survived:
            b += [.event(.haptic(.success)), .event(.play(SoundCue(.survive))), .say("training_good")]
            trainingTries = Self.practiceRounds
        case let .caught(reason):
            trainingTries += 1
            b += [.event(.play(SoundCue(.hit))), .event(.haptic(.hit)), .say(reason)]
            if trainingTries < Self.practiceRounds {
                b.append(.say(trainingTries == 1 ? "training_again_1" : "training_again_2"))
                beats += b + nextRound(c)
                return
            }
            b.append(.say("training_done"))
        }
        // Practice is over: the real one.
        training = nil
        learned.insert(c)
        events.append(.learned(c))
        beats += b + [.say("training_real")] + nextRound(c)
    }

    private func startEncounter(_ c: Creature) {
        encounter = pending ?? Encounter(creature: c, difficulty: difficulty, rng: RNG(seed: run.rng.next()), language: language)
        pending = nil
        phase = .encounter
    }

    private func finishEncounter(_ outcome: Encounter.Outcome) {
        let creature = encounter?.creature
        encounter = nil
        phase = .busy
        if let c = training, practice == nil {
            finishPractice(c, outcome)
            return
        }
        if practice != nil {
            switch outcome {
            case .survived:
                events.append(.achievement("practice"))
                beats += [.event(.haptic(.success)), .event(.play(SoundCue(.survive))), .say(variant("survived")), .step(.practiceOver)]
            case let .caught(reason):
                beats += [.event(.play(SoundCue(.hit))), .event(.haptic(.hit)), .say(reason), .step(.practiceOver)]
            }
            return
        }
        switch outcome {
        case .survived:
            run.stats.survived += 1
            if let creature { events.append(.achievement(creature == .echo ? "solve_echo" : "survive_\(creature.rawValue)")) }
            if creature == .echo || creature == .sleeper {
                let n = earn(creature == .sleeper ? 6 + Int((2 * difficulty).rounded()) : 4 + Int((2 * difficulty).rounded()))
                beats += [.event(.haptic(.success)), .event(.play(SoundCue(.coins))),
                          .say(creature == .sleeper ? "sleeper_reward" : "echo_reward"), .say(tokenLine(n)),
                          .wait(0.3), .step(.finishRoom)]
            } else {
                let n = earn(1)
                beats += [.event(.haptic(.success)), .say(variant("survived")), .event(.caption("+\(n)")), .wait(0.3), .step(.finishRoom)]
            }
        case let .caught(reason):
            var b: [Beat] = [.event(.play(SoundCue(.hit))), .event(.haptic(.hit)), .say(reason)]
            if run.count(.charm) > 0 {
                take(.charm)
                b += [.event(.play(SoundCue(.charmBreak))), .say("charm_saved"), .step(.finishRoom)]
            } else {
                run.health -= 1
                run.stats.hits += 1
                if run.health <= 0, run.count(.secondChance) > 0 {
                    take(.secondChance)
                    run.health = 1
                    events.append(.achievement("second_chance"))
                    b += [.event(.play(SoundCue(.heal))), .event(.haptic(.success)), .say("second_chance_saved"), .step(.finishRoom)]
                } else if run.health <= 0 {
                    b += [.step(.lose)]
                } else {
                    b += [.say("hurt_\(run.health)"), .step(.finishRoom)]
                }
            }
            beats += b
        }
    }

    private func finishRoom() {
        if run.coinDoors > 0 { run.coinDoors -= 1 }
        if run.step < Self.roomsPerHour {
            run.step += 1
            showDoors()
        } else if run.hour >= Self.hours {
            end(won: true)
        } else if Self.shopHours.contains(run.hour) {
            openShop()
        } else {
            run.hour += 1
            run.step = 1
            showDoors()
        }
    }

    // MARK: The shop

    private func openShop() {
        phase = .shop
        run.atShop = true
        events.append(.save)
        beats += [.event(.music(.calm)), .event(.ambience(.shop)), .say(variant("shop_welcome"))]
    }

    private func buy(_ item: Item) {
        interrupt()
        guard run.tokens >= item.price else {
            beats = [.say("shop_poor")]
            return
        }
        run.tokens -= item.price
        run.items[item.rawValue, default: 0] += 1
        events.append(.achievement("shopper"))
        beats = [.event(.play(SoundCue(.coins))), .say(variant("shop_buy"))]
    }

    private func leaveShop() {
        interrupt()
        phase = .busy
        run.atShop = false
        beats = [.say("shop_bye"), .step(.nextHour)]
    }

    // MARK: The end

    private func end(won: Bool) {
        phase = won ? .won : .lost
        if won {
            events.append(.achievement("first_night"))
            if run.health == 1 { events.append(.achievement("last_heart")) }
            if run.stats.hits == 0 { events.append(.achievement("untouchable")) }
        }
        beats += [.event(.music(won ? .win : .lose)), .event(.ambience(nil)),
                  .event(.play(SoundCue(won ? .winSting : .loseSting))), .wait(1.0),
                  .say(variant(won ? "win" : "lose")), .event(.ended(won: won))]
    }
}

extension Creature {
    /// What it sounds like through the door. (The Mimic copies a good room instead.)
    public var hint: Sfx {
        switch self {
        case .drip: return .hintDrip
        case .staticBuzz: return .hintStatic
        case .crawler: return .hintCrawler
        case .counter: return .hintCounter
        case .mimic: return .hintEmpty
        case .echo: return .hintEcho
        case .neighbor: return .hintNeighbor
        case .lullaby: return .hintLullaby
        case .breather: return .hintBreather
        case .twins: return .hintTwins
        case .lights: return .hintLights
        case .sleeper: return .hintSleeper
        }
    }
}
