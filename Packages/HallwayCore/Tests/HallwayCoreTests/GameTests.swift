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
                             "lighter_left", "lighter_right"] as Set<String>
        let unused = HostScript.lines.map(\.id).filter { !said.contains($0) && !notByBot.contains($0) && !$0.hasPrefix("see_") }
        XCTAssertEqual(unused, [], "lines never used")
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

    /// Writes the Host's lines for tools/make_voices.py: DUMP_PATH=/path/host_lines.json swift test --filter Dump
    func testDumpScript() throws {
        guard let path = ProcessInfo.processInfo.environment["DUMP_PATH"] else { return }
        let rows = HostScript.lines.map { ["id": $0.id, "lewis": $0.lewis, "heart": $0.heart] }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
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

    func required(_ c: Creature, seed: UInt64 = 1) -> (input: Input, from: Double, to: Double) {
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

    func testMimicTapReplays() {
        var e = Encounter(creature: .mimic, difficulty: 0, rng: RNG(seed: 2))
        _ = e.update(5)
        _ = e.input(.tap)
        var sounds = 0
        for _ in 0..<60 { sounds += e.update(1.0 / 30).filter { if case .play = $0 { return true }; return false }.count }
        XCTAssertEqual(sounds, 2)
    }
}
