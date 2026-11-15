/// A creature encounter: a short, real-time listening challenge.
///
/// Each one is a timeline of sounds plus a few rules: "you must swipe down between these two moments",
/// "don't touch anything until then". Difficulty (0 at hour 1, 1 at hour 24) makes windows shorter and
/// adds rounds and tricks. Everything is decided from the seed when the encounter starts.
public struct Encounter: Sendable {
    public enum Outcome: Equatable, Sendable {
        case survived
        /// The Host line that explains what went wrong.
        case caught(String)
    }

    struct Rule: Sendable {
        enum Kind: Sendable {
            /// Do `input` between `from` and `to`. A `wrong` input in that time gets you caught.
            case require(Input, wrong: [Input], ends: Bool, success: [GameEvent])
            /// Any of these inputs between `from` and `to` gets you caught.
            case forbid([Input])
        }
        var from: Double
        var to: Double
        var kind: Kind
        var reason: String
        var done = false
    }

    public let creature: Creature
    public let difficulty: Double
    public private(set) var time: Double = 0
    public private(set) var outcome: Outcome?
    var schedule: [(time: Double, event: GameEvent)] = []
    var rules: [Rule] = []
    var end: Double = 0
    var rng: RNG
    // The Mimic
    var realSide: Side = .left
    var fakeRate: Double = 1
    var mimicVoice: Sfx = .mimicVoice1

    static let actions: [Input] = [.left, .right, .up, .down, .tap]

    public init(creature: Creature, difficulty: Double, rng: RNG) {
        self.creature = creature
        self.difficulty = min(max(difficulty, 0), 1)
        self.rng = rng
        switch creature {
        case .drip: buildDrip()
        case .staticBuzz: buildStatic()
        case .crawler: buildCrawler()
        case .counter: buildCounter()
        case .mimic: buildMimic()
        }
        schedule.sort { $0.time < $1.time }
    }

    // MARK: Running

    /// Moves time forward. Returns the sounds and other events that happen.
    public mutating func update(_ dt: Double) -> [GameEvent] {
        guard outcome == nil else { return [] }
        time += dt
        var out: [GameEvent] = []
        while let first = schedule.first, first.time <= time {
            out.append(first.event)
            schedule.removeFirst()
        }
        for i in rules.indices where !rules[i].done {
            if case .require = rules[i].kind, time > rules[i].to {
                outcome = .caught(rules[i].reason)
                return out
            }
        }
        if time >= end, rules.allSatisfy({ rule in
            if case .require = rule.kind { return rule.done }
            return true
        }) {
            outcome = .survived
        }
        return out
    }

    public mutating func input(_ input: Input) -> [GameEvent] {
        guard outcome == nil, Self.actions.contains(input) else { return [] }
        if creature == .mimic, input == .tap {
            replayMimic(from: time + 0.2)
            return []
        }
        for i in rules.indices where !rules[i].done && rules[i].from <= time && time <= rules[i].to {
            switch rules[i].kind {
            case let .forbid(inputs):
                if inputs.contains(input) {
                    outcome = .caught(rules[i].reason)
                    return []
                }
            case let .require(needed, wrong, ends, success):
                if input == needed {
                    rules[i].done = true
                    if ends { outcome = .survived }
                    return success
                }
                if wrong.contains(input) {
                    outcome = .caught(rules[i].reason)
                    return []
                }
            }
        }
        return []
    }

    /// For the test bot: the right move and the earliest moment it counts.
    public var nextRequired: (input: Input, from: Double, to: Double)? {
        for rule in rules where !rule.done {
            if case let .require(input, _, _, _) = rule.kind { return (input, rule.from, rule.to) }
        }
        return nil
    }

    // MARK: The creatures

    private mutating func at(_ t: Double, _ e: GameEvent) { schedule.append((t, e)) }

    private mutating func buildDrip() {
        let d = difficulty
        let side = rng.side()
        let drips = rng.int(6, 9)
        var t = 0.8, gap = 0.95
        for k in 0..<drips {
            t += gap
            let v = 0.3 + 0.65 * Double(k) / Double(drips - 1)
            at(t, .play(SoundCue(rng.pick([.drip1, .drip2, .drip3]), pan: side.pan * 0.6, volume: v)))
            if k == 0 { at(t, .caption("Drip…")) }
            gap *= 0.80 - 0.06 * d
        }
        let splash = t + 0.55
        at(splash, .play(SoundCue(.splash, pan: side.pan * 0.4)))
        at(splash, .haptic(.warning))
        at(splash, .caption("SPLASH!"))
        let window = 1.4 - 0.6 * d
        rules.append(Rule(from: 0, to: splash - 0.05, kind: .forbid([.down]), reason: "caught_drip_early"))
        rules.append(Rule(from: splash - 0.05, to: splash + window,
                          kind: .require(.down, wrong: [], ends: false,
                                         success: [.play(SoundCue(.locker)), .haptic(.light), .caption("You hide.")]),
                          reason: "caught_drip_late"))
        end = splash + window + 0.8
    }

    private mutating func buildStatic() {
        let d = difficulty
        let rounds = 3 + Int((2 * d).rounded())
        let window = 1.7 - 0.8 * d
        var t = 1.0
        for _ in 0..<rounds {
            t += rng.range(0.6, 1.5) - 0.3 * d
            let side = rng.side()
            at(t, .play(SoundCue(.buzz, pan: side.pan)))
            at(t, .caption(side == .left ? "Bzzt! (left)" : "Bzzt! (right)"))
            let away: Input = side == .left ? .right : .left
            let toward: Input = side == .left ? .left : .right
            rules.append(Rule(from: t - 0.05, to: t + window,
                              kind: .require(away, wrong: [toward], ends: false, success: [.haptic(.light)]),
                              reason: "caught_static"))
            t += window
        }
        end = t + 0.3
        at(end - 0.1, .play(SoundCue(.zapOut)))
    }

    private mutating func buildCrawler() {
        let d = difficulty
        let rounds = 2 + (d > 0.5 ? 1 : 0)
        let window = 1.5 - 0.6 * d
        var t = 0.8
        for round in 0..<rounds {
            let roundStart = t
            let steps = rng.int(4, 6)
            var gap = 0.65
            for k in 0..<steps {
                t += gap
                let v = 0.25 + 0.65 * Double(k) / Double(steps - 1)
                at(t, .play(SoundCue(rng.pick([.crawl1, .crawl2, .crawl3]), pan: rng.range(-0.25, 0.25), volume: v)))
                gap *= 0.9
            }
            if round == 0 { at(roundStart + 0.65, .caption("Something crawls closer…")) }
            t += 0.45
            let growls = round == rounds - 1 || rng.chance(0.45)
            if growls {
                at(t, .play(SoundCue(.growl)))
                at(t, .haptic(.heavy))
                at(t, .caption("GROWL!"))
                rules.append(Rule(from: roundStart, to: t - 0.05, kind: .forbid([.up]), reason: "caught_crawler_early"))
                rules.append(Rule(from: t - 0.05, to: t + window,
                                  kind: .require(.up, wrong: [], ends: true,
                                                 success: [.play(SoundCue(.runAway)), .caption("You run!")]),
                                  reason: "caught_crawler_late"))
                end = t + window + 0.1
                return
            }
            at(t, .play(SoundCue(.sniff)))
            at(t, .caption("Sniff… sniff…"))
            rules.append(Rule(from: roundStart, to: t - 0.05, kind: .forbid([.up]), reason: "caught_crawler_early"))
            let still = 2.4 + 0.6 * d
            rules.append(Rule(from: t - 0.05, to: t + still, kind: .forbid(Self.actions), reason: "caught_crawler_moved"))
            t += still
            for k in 0..<3 {
                t += 0.5
                at(t, .play(SoundCue(rng.pick([.crawl1, .crawl2, .crawl3]), pan: 0, volume: 0.6 - 0.18 * Double(k))))
            }
            t += 0.6
        }
        end = t
    }

    private mutating func buildCounter() {
        let d = difficulty
        let gap = 1.0 - 0.3 * d
        let start = 1.0
        for n in stride(from: 10, through: 1, by: -1) {
            at(start + Double(10 - n) * gap, .play(SoundCue(.count(n), pan: rng.range(-0.3, 0.3))))
        }
        at(start, .caption("It starts counting…"))
        let sigh = start + 9 * gap + gap * 1.3
        let decoys = rng.int(0, Int((3 * d).rounded()))
        for _ in 0..<decoys {
            let t = rng.range(start + gap, sigh - gap)
            at(t, .play(SoundCue(rng.chance(0.5) ? .decoyKnock : .decoyCreak, pan: rng.chance(0.5) ? -0.8 : 0.8, volume: 0.8)))
        }
        at(sigh, .play(SoundCue(.counterSigh)))
        at(sigh, .caption("It sighs and leaves."))
        rules.append(Rule(from: 0.3, to: sigh, kind: .forbid(Self.actions), reason: "caught_counter"))
        end = sigh + 0.4
    }

    private mutating func buildMimic() {
        let d = difficulty
        realSide = rng.side()
        fakeRate = 0.76 + 0.14 * d
        mimicVoice = rng.pick([.mimicVoice1, .mimicVoice2, .mimicVoice3])
        at(0.2, .caption("Two voices. Which one is real?"))
        let limit = 10 - 3 * d
        var t = 0.6
        while t < limit - 1 {
            pair(at: t)
            t += 3.4
        }
        let real: Input = realSide == .left ? .left : .right
        let fake: Input = realSide == .left ? .right : .left
        rules.append(Rule(from: 0.6, to: limit,
                          kind: .require(real, wrong: [fake], ends: true,
                                         success: [.play(SoundCue(.survive)), .caption("It was the Mimic on the other side.")]),
                          reason: "caught_mimic"))
        end = limit
    }

    private mutating func pair(at t: Double) {
        for (k, side) in [Side.left, .right].enumerated() {
            at(t + Double(k) * 1.4, .play(SoundCue(mimicVoice, pan: side.pan, rate: side == realSide ? 1 : fakeRate)))
        }
    }

    private mutating func replayMimic(from t: Double) {
        schedule.removeAll { if case .play = $0.event { return true }; return false }
        pair(at: t)
        schedule.sort { $0.time < $1.time }
    }
}
