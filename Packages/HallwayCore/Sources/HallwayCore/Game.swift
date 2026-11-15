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

    public init(seed: UInt64) { rng = RNG(seed: seed) }

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

    enum Step: Sendable { case showDoors, shop, enter(Room), encounter(Creature), finishRoom, nextHour, win, lose }

    enum Beat: Sendable {
        case say(String)
        case wait(Double)
        case event(GameEvent)
        case step(Step)
    }

    public let host: Host
    public private(set) var run: RunState
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
    public init(host: Host, seed: UInt64, tutorial: Bool) {
        self.host = host
        run = RunState(seed: seed)
        beats = tutorial
            ? [.event(.music(.early)), .event(.ambience(.hallway)), .say("intro_1"), .say("intro_2"), .say("intro_3"), .say("intro_4"), .step(.showDoors)]
            : [.event(.music(.early)), .event(.ambience(.hallway)), .say("new_run"), .step(.showDoors)]
    }

    /// Continues a saved run at the start of its hour.
    public init(host: Host, resume: RunState) {
        self.host = host
        run = resume
        beats = [.event(.music(Self.track(for: resume.hour))), .say("welcome_back"), .step(resume.atShop ? .shop : .showDoors)]
    }

    /// Nothing is playing or being said: the player has heard everything.
    public var isIdle: Bool { beats.isEmpty && !waitingForHost && pause <= 0 }

    /// 0 at the first door, 1 at the very last one.
    public var difficulty: Double {
        Double((run.hour - 1) * Self.roomsPerHour + run.step - 1) / Double(Self.hours * Self.roomsPerHour - 1)
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
            case .use(.lighter): useLighter()
            case .use(.bandage): useBandage()
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
            b.append(.event(.caption(side == .left ? "Left door…" : "Right door…")))
            b.append(.event(.play(SoundCue(door.hint, pan: side.pan, volume: quiet, rate: door.rate, muffled: true))))
            b.append(.wait(2.0))
        }
        return b
    }

    private func listen() {
        interrupt()
        beats = hintBeats()
    }

    private func useLighter() {
        guard run.count(.lighter) > 0 else {
            interrupt()
            beats = [.say("lighter_none")]
            return
        }
        interrupt()
        run.items[Item.lighter.rawValue, default: 0] -= 1
        beats = [.say("lighter_left"), .say("see_\(run.doors[0].room.key)"), .say("lighter_right"), .say("see_\(run.doors[1].room.key)")]
    }

    private func useBandage() {
        interrupt()
        if run.count(.bandage) == 0 {
            beats = [.say("bandage_none")]
        } else if run.health >= Self.maxHealth {
            beats = [.say("bandage_full")]
        } else {
            run.items[Item.bandage.rawValue, default: 0] -= 1
            run.health += 1
            beats = [.event(.play(SoundCue(.heal))), .event(.haptic(.success)), .say("bandage_used")]
        }
    }

    private func choose(_ side: Side) {
        guard run.doors.count == 2 else { return }
        interrupt()
        let door = run.doors[side == .left ? 0 : 1]
        run.doors = []
        phase = .busy
        var b: [Beat] = []
        if run.rng.chance(0.35) { b.append(.say(variant("open"))) }
        b += [.event(.play(SoundCue(.doorOpen, pan: side.pan * 0.6))), .event(.haptic(.light)), .wait(1.0), .step(.enter(door.room))]
        beats = b
    }

    func makeDoors() -> [Door] {
        let d = difficulty
        let creatures = Creature.allCases.filter { $0.firstHour <= run.hour }.map { ($0, $0 == .mimic ? 1 + d : 1.0) }
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
        return doors
    }

    // MARK: Rooms

    private func enter(_ room: Room) {
        self.room = room
        switch room {
        case let .safe(kind):
            run.stats.safeRooms += 1
            var b: [Beat] = [.event(.ambience(.room)), .event(.caption(kind.name))]
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
                let n = run.rng.weighted([(1, 1.0), (2, 2.0), (3, 0.7)])
                run.tokens += n
                run.stats.tokensEarned += n
                b += [.event(.play(SoundCue(.coins))), .say(variant("room_vault")), .say("tokens_\(n)")]
            case .storage:
                let item = run.rng.weighted([(Item.lighter, 3.0), (.bandage, 1.0), (.charm, 0.4)])
                run.items[item.rawValue, default: 0] += 1
                b += [.event(.play(SoundCue(.itemGet))), .say(variant("room_storage")), .say("found_\(item.rawValue)")]
            case .empty:
                b += [.event(.play(SoundCue(.nothing))), .say(variant("room_empty"))]
            }
            beats += b + [.wait(0.6), .step(.finishRoom)]
        case let .creature(c):
            let first = !run.met.contains(c)
            if first { run.met.append(c) }
            beats += [.event(.music(nil)), .event(.ambience(nil)), .event(.caption(c.name)),
                      .event(.play(SoundCue(.heartbeat))), .event(.haptic(.heartbeat)),
                      .say(first ? "learn_\(c.rawValue)" : "meet_\(c.rawValue)"), .wait(0.3), .step(.encounter(c))]
        }
    }

    private func startEncounter(_ c: Creature) {
        encounter = Encounter(creature: c, difficulty: difficulty, rng: RNG(seed: run.rng.next()))
        phase = .encounter
    }

    private func finishEncounter(_ outcome: Encounter.Outcome) {
        encounter = nil
        phase = .busy
        switch outcome {
        case .survived:
            run.stats.survived += 1
            beats += [.event(.haptic(.success)), .say(variant("survived")), .wait(0.3), .step(.finishRoom)]
        case let .caught(reason):
            var b: [Beat] = [.event(.play(SoundCue(.hit))), .event(.haptic(.heavy)), .say(reason)]
            if run.count(.charm) > 0 {
                run.items[Item.charm.rawValue, default: 0] -= 1
                b += [.event(.play(SoundCue(.charmBreak))), .say("charm_saved"), .step(.finishRoom)]
            } else {
                run.health -= 1
                run.stats.hits += 1
                if run.health <= 0 {
                    b += [.step(.lose)]
                } else {
                    b += [.say("hurt_\(run.health)"), .step(.finishRoom)]
                }
            }
            beats += b
        }
    }

    private func finishRoom() {
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
        }
    }
}
