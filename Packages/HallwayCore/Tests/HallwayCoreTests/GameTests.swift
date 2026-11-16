import Foundation
import XCTest
@testable import HallwayCore

final class GameTests: XCTestCase {
    let perfect = BotPlayer(skill: 1, ear: 1, reaction: 0.35, seed: 1)

    func testSameSeedSameRun() {
        let a = Simulator.play(seed: 42, bot: BotPlayer(skill: 0.85, ear: 0.6, reaction: 0.4, seed: 7)).0
        let b = Simulator.play(seed: 42, bot: BotPlayer(skill: 0.85, ear: 0.6, reaction: 0.4, seed: 7)).0
        XCTAssertEqual(a, b)
    }

    /// Perfect play always survives every creature, at every hour: no unfair encounter.
    func testPerfectPlayerAlwaysWins() {
        for seed in 1...150 as ClosedRange<UInt64> {
            let r = Simulator.play(seed: seed, bot: perfect).0
            XCTAssertTrue(r.won, "seed \(seed) lost at hour \(r.hour)")
            XCTAssertEqual(r.stats.hits, 0, "seed \(seed)")
        }
    }

    /// Still fair for a slower player (0.7 s to react).
    func testSlowButCorrectPlayerWins() {
        for seed in 1...60 as ClosedRange<UInt64> {
            let r = Simulator.play(seed: seed, bot: BotPlayer(skill: 1, ear: 1, reaction: 0.7, seed: seed)).0
            XCTAssertTrue(r.won, "seed \(seed) lost at hour \(r.hour)")
        }
    }

    /// Someone guessing loses almost every time; a good player wins sometimes. Prints the numbers.
    func testDifficulty() {
        func winRate(_ skill: Double, _ ear: Double) -> Double {
            let runs = (1...200 as ClosedRange<UInt64>).map {
                Simulator.play(seed: $0 &* 977, bot: BotPlayer(skill: skill, ear: ear, reaction: 0.45, seed: $0)).0
            }
            return Double(runs.filter(\.won).count) / Double(runs.count)
        }
        let bad = winRate(0.3, 0), okay = winRate(0.7, 0.3), good = winRate(0.85, 0.6), great = winRate(0.95, 0.9)
        print("Win rates: guessing \(bad), okay \(okay), good \(good), great \(great)")
        XCTAssertLessThan(bad, 0.05)
        XCTAssertGreaterThan(okay, 0.1)
        XCTAssertLessThan(okay, 0.7)
        XCTAssertGreaterThan(good, okay)
        XCTAssertLessThan(good, 0.97)
        XCTAssertGreaterThan(great, good)
    }

    /// With the Host's talking counted, a full run takes roughly half an hour.
    func testRunLength() {
        let times = (1...20 as ClosedRange<UInt64>).map { Simulator.play(seed: $0, bot: perfect, talk: true).0.seconds / 60 }
        let avg = times.reduce(0, +) / Double(times.count)
        print("A full run takes about \(Int(avg)) minutes (counting talk, not counting thinking)")
        XCTAssertGreaterThan(avg, 12)
        XCTAssertLessThan(avg, 60)
    }

    /// Every line the game says exists in the script, and (almost) every scripted line gets used.
    func testEveryLineExistsAndIsUsed() {
        var said = Set<String>()
        for seed in 1...400 as ClosedRange<UInt64> {
            let bot = BotPlayer(skill: seed % 3 == 0 ? 0.6 : 0.9, ear: 0.5, reaction: 0.4, seed: seed)
            for id in Simulator.play(seed: seed, bot: bot).0.lines {
                XCTAssertTrue(HostScript.has(id), "missing line \(id)")
                said.insert(id)
            }
        }
        // Not reached by the bot: it never asks for things it can't have, and never comes back.
        let notByBot: Set = ["welcome_back", "new_run", "lighter_none", "bandage_none", "bandage_full", "shop_poor",
                             "lighter_left", "lighter_right", "coin_none", "key_none", "practice_welcome"] as Set<String>
        let unused = HostScript.lines.map(\.id).filter {
            !said.contains($0) && !notByBot.contains($0) && !$0.hasPrefix("see_") && !$0.hasPrefix("tokens_")
        }
        XCTAssertEqual(unused, [], "lines never used")
    }

    /// Every achievement the game can send is a real one, and a winning night earns the main ones.
    func testAchievements() {
        var earned = Set<String>()
        for seed in 1...60 as ClosedRange<UInt64> {
            let game = Game(host: .lewis, seed: seed, tutorial: false)
            var bot = BotPlayer(skill: 1, ear: 1, reaction: 0.35, seed: seed)
            for _ in 0..<(30 * 60 * 90) {
                if game.waitingForHost { game.hostFinished() }
                if let i = bot.act(game) { game.input(i) }
                game.update(1.0 / 30)
                var done = false
                for e in game.drainEvents() {
                    if case let .achievement(id) = e {
                        XCTAssertNotNil(Achievement.named(id), "unknown achievement \(id)")
                        earned.insert(id)
                    }
                    if case .ended = e { done = true }
                }
                if done { break }
            }
        }
        for id in ["first_door", "survive_drip", "survive_static", "survive_crawler", "survive_counter", "survive_mimic",
                   "hour_12", "first_night", "untouchable", "shopper"] {
            XCTAssertTrue(earned.contains(id), "never earned \(id)")
        }
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count)
        XCTAssertLessThanOrEqual(Achievement.all.map(\.points).reduce(0, +), 1000)
    }

    /// The first time a creature shows up: up to three practice rounds that can't hurt, then the real one.
    func testPracticeRoundsBeforeANewCreature() {
        var state = RunState(seed: 21)
        state.doors = [Door(room: .creature(.counter), hint: .hintCounter), Door(room: .creature(.counter), hint: .hintCounter)]
        let game = Game(host: .lewis, resume: state)
        var said: [String] = [], learned: [Creature] = []
        var touched = false
        for _ in 0..<(30 * 200) {
            if game.waitingForHost { game.hostFinished() }
            if game.phase == .hallway, game.run.doors.count == 2 { game.input(.left) }
            // Touch during every practice round (the Counter catches that), then keep still for the real one.
            if game.phase == .encounter, game.training != nil, let e = game.encounter, e.time > 2, !touched {
                game.input(.tap); touched = true
            }
            if game.phase != .encounter { touched = false }
            game.update(1.0 / 30)
            for e in game.drainEvents() {
                if case let .say(id) = e { said.append(id) }
                if case let .learned(c) = e { learned.append(c) }
            }
            if said.contains("training_real") && game.phase == .hallway { break }
        }
        XCTAssertEqual(said.filter { $0 == "caught_counter" }.count, 3)
        XCTAssertTrue(said.contains("training_intro"))
        XCTAssertTrue(said.contains("training_done"))
        XCTAssertEqual(learned, [.counter])
        XCTAssertEqual(game.run.health, Game.maxHealth, "practice rounds never cost a heart")
        XCTAssertTrue(game.learned.contains(.counter))
    }

    func testLearnedCreaturesSkipPractice() {
        let r = Simulator.play(seed: 3, bot: perfect, learned: Set(Creature.allCases)).0
        XCTAssertFalse(r.lines.contains("training_intro"))
    }

    func testLineIdsAreUnique() {
        XCTAssertEqual(Set(HostScript.lines.map(\.id)).count, HostScript.lines.count)
    }

    func testSaveAndContinue() throws {
        let (_, game) = Simulator.play(seed: 9, bot: perfect, stopAtHour: 8)
        XCTAssertEqual(game.run.hour, 8)
        let data = try JSONEncoder().encode(game.run)
        let saved = try JSONDecoder().decode(RunState.self, from: data)
        XCTAssertEqual(saved, game.run)
        let r = Simulator.play(seed: 9, bot: perfect, resume: saved).0
        XCTAssertTrue(r.won)
        XCTAssertEqual(r.lines.first, "welcome_back")
    }

    func testContinueInShop() {
        var state = RunState(seed: 3)
        state.hour = 6
        state.atShop = true
        state.tokens = 10
        let game = Game(host: .heart, resume: state)
        for _ in 0..<10 { game.update(0.1); if game.waitingForHost { game.hostFinished() } }
        XCTAssertEqual(game.phase, .shop)
        game.input(.buy(.charm))
        XCTAssertEqual(game.run.tokens, 10 - Item.charm.price)
        XCTAssertEqual(game.run.count(.charm), 1)
        game.input(.leave)
        for _ in 0..<10 { game.update(0.1); if game.waitingForHost { game.hostFinished() } }
        XCTAssertEqual(game.run.hour, 7)
        XCTAssertEqual(game.phase, .hallway)
        XCTAssertFalse(game.run.atShop)
    }

    func testLighterTellsTheTruth() {
        let game = Game(host: .lewis, seed: 5, tutorial: false)
        for _ in 0..<5 { game.update(0.1); if game.waitingForHost { game.hostFinished() } }
        XCTAssertEqual(game.phase, .hallway)
        let doors = game.run.doors
        _ = game.drainEvents()
        game.input(.use(.lighter))
        var said: [String] = []
        for _ in 0..<20 {
            game.update(0.1)
            for case let .say(id) in game.drainEvents() { said.append(id) }
            if game.waitingForHost { game.hostFinished() }
        }
        XCTAssertEqual(Array(said.prefix(4)), ["lighter_left", "see_\(doors[0].room.key)", "lighter_right", "see_\(doors[1].room.key)"])
        XCTAssertEqual(game.run.count(.lighter), 0)
    }

    func testMimicDoorsSoundLower() {
        for seed in 1...300 as ClosedRange<UInt64> {
            var state = RunState(seed: seed)
            state.hour = 20
            let game = Game(host: .lewis, resume: state)
            for door in game.makeDoors() where door.room == .creature(.mimic) {
                XCTAssertLessThan(door.rate, 1)
                XCTAssertTrue(SafeRoom.allCases.map(\.hint).contains(door.hint))
            }
        }
    }

    /// Writes every Host's lines for tools/make_voices.py: DUMP_PATH=/path/host_lines.json swift test --filter Dump
    func testDumpScript() throws {
        guard let path = ProcessInfo.processInfo.environment["DUMP_PATH"] else { return }
        let hosts: [[String: Any]] = Host.allCases.map { h in
            ["host": h.rawValue, "voice": h.voice.id, "speed": h.voice.speed, "lang": h.voice.lang,
             "lines": Dictionary(uniqueKeysWithValues: HostScript.ids.map { ($0, HostScript.text($0, h)) })]
        }
        let data = try JSONSerialization.data(withJSONObject: hosts, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Every Host can say every line, in their own language, and personal lines only replace real ones.
    func testEveryHostHasEveryLine() {
        for host in Host.allCases {
            for id in HostScript.ids {
                let text = HostScript.text(id, host)
                XCTAssertNotEqual(text, id, "\(host) has no line \(id)")
                XCTAssertFalse(text.isEmpty, "\(host) \(id)")
            }
            for id in HostScript.overrides[host]?.keys ?? [:].keys {
                XCTAssertTrue(HostScript.has(id), "\(host) overrides unknown line \(id)")
            }
        }
        for id in HostScript.pt.keys { XCTAssertTrue(HostScript.has(id), "Portuguese has unknown line \(id)") }
    }

    /// Every Host can play a whole night.
    func testEveryHostPlays() {
        for (i, host) in Host.allCases.enumerated() {
            let r = Simulator.play(seed: UInt64(i + 1), host: host, bot: perfect).0
            XCTAssertTrue(r.won, "\(host)")
        }
    }

    func testPracticeRoom() {
        let game = Game(host: .alex, practice: .drip, difficulty: 0.5, seed: 4, welcome: true)
        var said: [String] = []
        func run(_ seconds: Double, input: (Game) -> Input? = { _ in nil }) {
            for _ in 0..<Int(seconds * 30) {
                if game.waitingForHost { game.hostFinished() }
                if let i = input(game) { game.input(i) }
                game.update(1.0 / 30)
                for case let .say(id) in game.drainEvents() { said.append(id) }
            }
        }
        run(20)
        XCTAssertEqual(game.phase, .practiceOver)
        XCTAssertEqual(Array(said.prefix(2)), ["practice_welcome", "learn_drip"])
        XCTAssertEqual(said.last, "caught_drip_late")
        XCTAssertEqual(game.run.health, Game.maxHealth)
        game.input(.again)
        var bot = BotPlayer(skill: 1, ear: 1, reaction: 0.3, seed: 1)
        run(20) { bot.act($0) }
        XCTAssertEqual(game.phase, .practiceOver)
        XCTAssertTrue(said.contains("meet_drip"))
        XCTAssertTrue(HostScript.variants("survived").contains(said.last ?? ""))
    }

    func testSecondChanceAndCharm() {
        var state = RunState(seed: 8)
        state.health = 1
        state.items = [Item.secondChance.rawValue: 1]
        let bad = BotPlayer(skill: 0, ear: 0, reaction: 0.4, seed: 2)
        let r = Simulator.play(seed: 8, bot: bad, resume: state).0
        XCTAssertTrue(r.lines.contains("second_chance_saved"))
        XCTAssertFalse(r.won)
    }

    func testOldSavesStillLoad() throws {
        let old = #"{"rng":{"state":5},"hour":7,"step":2,"health":2,"tokens":3,"items":{"lighter":1},"doors":[],"met":["drip"],"stats":{"survived":1,"hits":1,"safeRooms":4,"tokensEarned":3},"atShop":false}"#
        let state = try JSONDecoder().decode(RunState.self, from: Data(old.utf8))
        XCTAssertEqual(state.hour, 7)
        XCTAssertEqual(state.coinDoors, 0)
    }
}

final class EncounterTests: XCTestCase {
    /// Runs an encounter, doing `input` at time `at` (nil: never touch anything).
    func run(_ c: Creature, _ d: Double = 0.5, seed: UInt64 = 1, input: Input? = nil, at: Double? = nil) -> Encounter.Outcome? {
        var e = Encounter(creature: c, difficulty: d, rng: RNG(seed: seed))
        var done = false
        for _ in 0..<2000 {
            _ = e.update(1.0 / 30)
            if let input, let at, !done, e.time >= at { _ = e.input(input); done = true }
            if e.outcome != nil { break }
        }
        return e.outcome
    }

    func required(_ c: Creature, seed: UInt64 = 1) -> (input: Input, from: Double, to: Double, onBeat: Bool) {
        Encounter(creature: c, difficulty: 0.5, rng: RNG(seed: seed)).nextRequired!
    }

    func testDrip() {
        let need = required(.drip)
        XCTAssertEqual(need.input, .down)
        XCTAssertEqual(run(.drip, input: .down, at: need.from + 0.3), .survived)
        XCTAssertEqual(run(.drip, input: .down, at: 1.0), .caught("caught_drip_early"))
        XCTAssertEqual(run(.drip), .caught("caught_drip_late"))
    }

    func testCounterMeansDontTouch() {
        XCTAssertEqual(run(.counter), .survived)
        XCTAssertEqual(run(.counter, input: .tap, at: 3), .caught("caught_counter"))
    }

    func testStaticWrongWay() {
        let need = required(.staticBuzz)
        let wrong: Input = need.input == .left ? .right : .left
        XCTAssertEqual(run(.staticBuzz, input: wrong, at: need.from + 0.2), .caught("caught_static"))
        XCTAssertEqual(run(.staticBuzz), .caught("caught_static"))
    }

    func testCrawlerRunningEarly() {
        XCTAssertEqual(run(.crawler, input: .up, at: 1.5), .caught("caught_crawler_early"))
    }

    func testMimicWrongVoice() {
        let need = required(.mimic)
        let wrong: Input = need.input == .left ? .right : .left
        XCTAssertEqual(run(.mimic, input: wrong, at: 2), .caught("caught_mimic"))
        XCTAssertEqual(run(.mimic, input: need.input, at: 3.5), .survived)
        XCTAssertEqual(run(.mimic), .caught("caught_mimic"))
    }

    func testEchoSolvedByPlayingItBack() {
        var e = Encounter(creature: .echo, difficulty: 0.2, rng: RNG(seed: 3))
        var steps = 0
        while e.outcome == nil, steps < 3000 {
            _ = e.update(1.0 / 30)
            if let need = e.nextRequired, e.time >= need.from + 0.3 { _ = e.input(need.input) }
            steps += 1
        }
        XCTAssertEqual(e.outcome, .survived)
        XCTAssertEqual(e.mistakes, 0)
    }

    func testEchoThreeMistakes() {
        var e = Encounter(creature: .echo, difficulty: 0.8, rng: RNG(seed: 3))
        var steps = 0
        while e.outcome == nil, steps < 5000 {
            _ = e.update(1.0 / 30)
            if let need = e.nextRequired, e.time >= need.from + 0.3 {
                _ = e.input(need.input == .tap ? .up : .tap)
            }
            steps += 1
        }
        XCTAssertEqual(e.outcome, .caught("caught_echo"))
        XCTAssertEqual(e.mistakes, 3)
    }

    func testEchoWaitingTooLongIsAMistake() {
        var e = Encounter(creature: .echo, difficulty: 0, rng: RNG(seed: 9))
        for _ in 0..<(60 * 30) { _ = e.update(1.0 / 30) }
        XCTAssertEqual(e.outcome, .caught("caught_echo"))
    }

    func testStaticZapsOnEachRightSwipe() {
        var e = Encounter(creature: .staticBuzz, difficulty: 0.5, rng: RNG(seed: 1))
        var zaps = 0
        for _ in 0..<2000 where e.outcome == nil {
            _ = e.update(1.0 / 30)
            if let need = e.nextRequired, e.time >= need.from + 0.3 {
                zaps += e.input(need.input).filter { if case let .play(c) = $0 { return c.sfx == .zap }; return false }.count
            }
        }
        XCTAssertEqual(e.outcome, .survived)
        XCTAssertEqual(zaps, e.rounds)
    }

    /// Plays an encounter with a perfect player (or one that does `mistake` instead of each right move).
    func play(_ c: Creature, _ d: Double, seed: UInt64 = 1, wrong: Bool = false) -> Encounter {
        var e = Encounter(creature: c, difficulty: d, rng: RNG(seed: seed))
        for _ in 0..<(30 * 120) where e.outcome == nil {
            _ = e.update(1.0 / 30)
            if let need = e.nextRequired, e.time >= need.from + (need.onBeat ? 0 : 0.35) {
                if wrong {
                    _ = e.input(need.input == .left ? .right : need.input == .right ? .left : .up)
                } else {
                    _ = e.input(need.input)
                }
            }
        }
        return e
    }

    func testNewCreaturesCanBeBeatenAndLost() {
        for c in [Creature.neighbor, .lullaby, .breather, .twins, .lights] {
            for d in [0.0, 0.5, 1.0] {
                for seed in 1...5 as ClosedRange<UInt64> {
                    XCTAssertEqual(play(c, d, seed: seed).outcome, .survived, "\(c) at \(d), seed \(seed)")
                    XCTAssertEqual(play(c, d, seed: seed, wrong: true).outcome, .caught("caught_\(c.rawValue)"), "\(c) at \(d)")
                }
            }
        }
    }

    func testNeighborWrongCount() {
        var e = Encounter(creature: .neighbor, difficulty: 0, rng: RNG(seed: 4))
        var tapped = false
        for _ in 0..<(30 * 60) where e.outcome == nil {
            _ = e.update(1.0 / 30)
            // One tap too many each time.
            if let need = e.nextRequired, e.time >= need.from + 0.3, !tapped {
                for _ in 0...e.knocks { _ = e.input(.tap) }
                tapped = true
            }
            if e.nextRequired == nil { tapped = false }
        }
        XCTAssertEqual(e.outcome, .caught("caught_neighbor"))
        XCTAssertEqual(e.mistakes, 2)
    }

    func testLightsOneMissIsForgiven() {
        var e = Encounter(creature: .lights, difficulty: 0, rng: RNG(seed: 1))
        var skipTick: Double?
        for _ in 0..<(30 * 60) where e.outcome == nil {
            _ = e.update(1.0 / 30)
            if let need = e.nextRequired, e.time >= need.from {
                if skipTick == nil { skipTick = need.from }   // miss the first tick that counts
                if need.from == skipTick { continue }
                _ = e.input(.tap)
            }
        }
        XCTAssertEqual(e.outcome, .survived)
        XCTAssertEqual(e.mistakes, 1)
    }

    func testMimicTapReplays() {
        var e = Encounter(creature: .mimic, difficulty: 0, rng: RNG(seed: 2))
        _ = e.update(5)
        _ = e.input(.tap)
        var sounds = 0
        for _ in 0..<60 { sounds += e.update(1.0 / 30).filter { if case .play = $0 { return true }; return false }.count }
        XCTAssertEqual(sounds, 2)
    }
}
