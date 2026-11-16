/// A creature encounter (or the Echo puzzle): a short, real-time listening challenge.
///
/// Each creature is a timeline of sounds plus a few rules: "you must swipe down between these two moments",
/// "don't touch anything until then". Difficulty (0 at the first door, 1 at the last) makes windows shorter and
/// adds rounds and tricks. Everything is decided from the seed when the encounter starts.
/// The Echo works differently: it plays a pattern, then waits for you to play it back.
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
    public let language: Language
    public private(set) var time: Double = 0
    public private(set) var outcome: Outcome?
    /// Static: how many buzzes are coming.
    public private(set) var rounds = 0
    var schedule: [(time: Double, event: GameEvent)] = []
    var rules: [Rule] = []
    var end: Double = 0
    var rng: RNG
    // The Mimic
    var realSide: Side = .left
    var fakeRate: Double = 1
    var mimicVoice: Sfx = .mimicVoice1
    // The Echo
    var pattern: [Input] = []
    var echoRound = 0
    var echoIndex = 0
    var listenFrom = Double.infinity
    var deadline = Double.infinity
    /// Echo: mistakes so far (three and it shrieks).
    public private(set) var mistakes = 0

    static let actions: [Input] = [.left, .right, .up, .down, .tap]

    public init(creature: Creature, difficulty: Double, rng: RNG, language: Language = .en) {
        self.creature = creature
        self.difficulty = min(max(difficulty, 0), 1)
        self.rng = rng
        self.language = language
        switch creature {
        case .drip: buildDrip()
        case .staticBuzz: buildStatic()
        case .crawler: buildCrawler()
        case .counter: buildCounter()
        case .mimic: buildMimic()
        case .echo: startEcho()
        }
        schedule.sort { $0.time < $1.time }
    }

    private func t(_ en: String, _ pt: String) -> String { language.t(en, pt) }

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
        if creature == .echo {
            if time > deadline { out += echoMistake() }
            return out
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
        if creature == .echo { return echoInput(input) }
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
        if creature == .echo {
            guard echoIndex < pattern.count, listenFrom.isFinite else { return nil }
            return (pattern[echoIndex], listenFrom, deadline)
        }
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
            if k == 0 { at(t, .caption(self.t("Drip…", "Pinga…"))) }
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
                                         success: [.play(SoundCue(.locker)), .haptic(.light), .caption(self.t("You hide.", "Você se esconde."))]),
                          reason: "caught_drip_late"))
        end = splash + window + 0.8
    }

    private mutating func buildStatic() {
        let d = difficulty
        rounds = 3 + Int((2 * d).rounded())
        let window = 1.7 - 0.8 * d
        var t = 1.2
        for _ in 0..<rounds {
            t += rng.range(0.6, 1.5) - 0.3 * d
            let side = rng.side()
            // Fully in one ear, so there's no doubt which side it's on.
            at(t, .play(SoundCue(.buzz, pan: side == .left ? -1 : 1)))
            at(t, .caption(side == .left ? t2("Bzzt! (left)", "Bzzt! (esquerda)") : t2("Bzzt! (right)", "Bzzt! (direita)")))
            let away: Input = side == .left ? .right : .left
            let toward: Input = side == .left ? .left : .right
            // A zap from the side you swiped to: you got it.
            let zap: [GameEvent] = [.play(SoundCue(.zap, pan: side == .left ? 0.7 : -0.7)), .haptic(.light)]
            rules.append(Rule(from: t - 0.05, to: t + window,
                              kind: .require(away, wrong: [toward], ends: false, success: zap),
                              reason: "caught_static"))
            t += window
        }
        end = t + 0.3
        at(end - 0.1, .play(SoundCue(.zapOut)))
        at(end - 0.1, .caption(t2("It fizzles out.", "Ela some com um chiado.")))
    }

    private func t2(_ en: String, _ pt: String) -> String { language.t(en, pt) }

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
            if round == 0 { at(roundStart + 0.65, .caption(t2("Something crawls closer…", "Algo rasteja mais perto…"))) }
            t += 0.45
            let growls = round == rounds - 1 || rng.chance(0.45)
            if growls {
                at(t, .play(SoundCue(.growl)))
                at(t, .haptic(.heavy))
                at(t, .caption(t2("GROWL!", "GRRR!")))
                rules.append(Rule(from: roundStart, to: t - 0.05, kind: .forbid([.up]), reason: "caught_crawler_early"))
                rules.append(Rule(from: t - 0.05, to: t + window,
                                  kind: .require(.up, wrong: [], ends: true,
                                                 success: [.play(SoundCue(.runAway)), .caption(t2("You run!", "Você corre!"))]),
                                  reason: "caught_crawler_late"))
                end = t + window + 0.1
                return
            }
            at(t, .play(SoundCue(.sniff)))
            at(t, .caption(t2("Sniff… sniff…", "Fareja… fareja…")))
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
        at(start, .caption(t2("It starts counting…", "Ele começa a contar…")))
        let sigh = start + 9 * gap + gap * 1.3
        let decoys = rng.int(0, Int((3 * d).rounded()))
        for _ in 0..<decoys {
            let t = rng.range(start + gap, sigh - gap)
            at(t, .play(SoundCue(rng.chance(0.5) ? .decoyKnock : .decoyCreak, pan: rng.chance(0.5) ? -0.8 : 0.8, volume: 0.8)))
        }
        at(sigh, .play(SoundCue(.counterSigh)))
        at(sigh, .caption(t2("It sighs and leaves.", "Ele suspira e vai embora.")))
        rules.append(Rule(from: 0.3, to: sigh, kind: .forbid(Self.actions), reason: "caught_counter"))
        end = sigh + 0.4
    }

    private mutating func buildMimic() {
        let d = difficulty
        realSide = rng.side()
        fakeRate = 0.76 + 0.14 * d
        mimicVoice = rng.pick([.mimicVoice1, .mimicVoice2, .mimicVoice3])
        at(0.2, .caption(t2("Two voices. Which one is real?", "Duas vozes. Qual é a real?")))
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
                                         success: [.play(SoundCue(.survive)),
                                                   .caption(t2("It was the Mimic on the other side.", "O Imitador estava do outro lado."))]),
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

    // MARK: The Echo

    static func echoPan(_ input: Input) -> Double {
        switch input {
        case .left: return -1
        case .right: return 1
        default: return 0
        }
    }

    /// How long the pattern is in a round.
    var echoLength: Int { 3 + Int((3 * difficulty).rounded()) + echoRound }
    var echoRounds: Int { difficulty < 0.4 ? 1 : 2 }

    private mutating func startEcho() {
        end = .infinity
        pattern = (0..<echoLength).map { _ in rng.pick(Self.actions) }
        playPattern(from: 0.8)
    }

    private var echoGap: Double { 0.8 - 0.25 * difficulty }

    /// Plays the pattern, then the "your turn" chime, then listens.
    private mutating func playPattern(from start: Double) {
        echoIndex = 0
        at(start, .caption(t2("Listen…", "Escute…")))
        for (i, move) in pattern.enumerated() {
            at(start + Double(i) * echoGap, .play(SoundCue(Sfx.echo(move), pan: Self.echoPan(move))))
        }
        let turn = start + Double(pattern.count) * echoGap + 0.2
        at(turn, .play(SoundCue(.echoTurn)))
        at(turn, .caption(t2("Your turn.", "Sua vez.")))
        listenFrom = turn
        deadline = turn + 5
        schedule.sort { $0.time < $1.time }
    }

    private mutating func echoInput(_ input: Input) -> [GameEvent] {
        guard time >= listenFrom - 0.1, echoIndex < pattern.count else { return [] }
        guard input == pattern[echoIndex] else { return echoMistake() }
        echoIndex += 1
        var out: [GameEvent] = [.play(SoundCue(Sfx.echo(input), pan: Self.echoPan(input)))]
        deadline = time + 4
        if echoIndex == pattern.count {
            echoRound += 1
            if echoRound >= echoRounds {
                outcome = .survived
                out += [.play(SoundCue(.echoSolved)), .caption(t2("Solved!", "Resolvido!"))]
            } else {
                out += [.haptic(.success), .caption(t2("Again, longer.", "De novo, mais longo."))]
                pattern = (0..<echoLength).map { _ in rng.pick(Self.actions) }
                listenFrom = .infinity
                deadline = .infinity
                playPattern(from: time + 1.2)
            }
        }
        return out
    }

    private mutating func echoMistake() -> [GameEvent] {
        mistakes += 1
        if mistakes >= 3 {
            outcome = .caught("caught_echo")
            return []
        }
        listenFrom = .infinity
        deadline = .infinity
        playPattern(from: time + 1.3)
        return [.play(SoundCue(.echoWrong)), .haptic(.warning),
                .caption(mistakes == 1 ? t2("Wrong. Two tries left.", "Errado. Mais duas chances.") : t2("Wrong. Last try.", "Errado. Última chance."))]
    }
}
