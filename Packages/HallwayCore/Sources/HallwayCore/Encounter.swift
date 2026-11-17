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
    /// Practice rounds and the Practice Room: the Echo whispers every move, whatever the hour.
    public let guided: Bool
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
    /// Echo: mistakes so far (three and it shrieks). The Neighbor, the Lullaby and the Lights allow fewer.
    public private(set) var mistakes = 0
    // The Neighbor
    var knocks = 0
    var taps = 0
    var lastTap = -10.0
    var judgeAt = Double.infinity
    var round = 0
    // The Lullaby: when each note comes, from the first one
    var beats: [Double] = []
    var pitches: [Double] = []
    var firstTap: Double?
    var noteIndex = 0
    var tolerance = 0.3
    // The Lights
    var ticks: [Double] = []
    var hit: [Bool] = []
    // The Sleeper
    static let spots: [Input] = [.left, .right, .up, .down]
    /// What's hidden in each place (left, right, ahead, behind): a number (1 to 6), or 0 for nothing.
    var hidden: [Int] = []
    var searched: [Bool] = [false, false, false, false]
    var code: [Int] = []
    var needed = 3
    var dialing = false
    var dialed: [Int] = []
    var lastAction = -10.0
    var nextSnore = 0.0
    var nextStir = 0.0
    var stirFrom = Double.infinity
    var stirTo = Double.infinity
    var wakeAt = Double.infinity

    static let actions: [Input] = [.left, .right, .up, .down, .tap]

    public init(creature: Creature, difficulty: Double, rng: RNG, language: Language = .en, guided: Bool = false) {
        self.creature = creature
        self.difficulty = min(max(difficulty, 0), 1)
        self.rng = rng
        self.language = language
        self.guided = guided
        switch creature {
        case .drip: buildDrip()
        case .staticBuzz: buildStatic()
        case .crawler: buildCrawler()
        case .counter: buildCounter()
        case .mimic: buildMimic()
        case .echo: startEcho()
        case .neighbor: startNeighbor()
        case .lullaby: startLullaby()
        case .breather: buildBreather()
        case .twins: buildTwins()
        case .lights: buildLights()
        case .sleeper: startSleeper()
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
        if creature == .neighbor { return out + neighborUpdate() }
        if creature == .lullaby { return out + lullabyUpdate() }
        if creature == .lights { return out + lightsUpdate() }
        if creature == .sleeper { return out + sleeperUpdate() }
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
        if creature == .neighbor { return neighborInput(input) }
        if creature == .lullaby { return lullabyInput(input) }
        if creature == .lights { return lightsInput(input) }
        if creature == .sleeper { return sleeperInput(input) }
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

    /// For the test bot: the right move and the earliest moment it counts. `onBeat`: tap exactly at `from`
    /// (a rhythm the player can anticipate), instead of reacting to a sound.
    public var nextRequired: (input: Input, from: Double, to: Double, onBeat: Bool)? {
        switch creature {
        case .echo:
            guard echoIndex < pattern.count, listenFrom.isFinite else { return nil }
            return (pattern[echoIndex], listenFrom, deadline, false)
        case .neighbor:
            guard listenFrom.isFinite, taps < knocks else { return nil }
            return (.tap, max(listenFrom, lastTap + 0.35), deadline, false)
        case .lullaby:
            guard listenFrom.isFinite, noteIndex < beats.count else { return nil }
            guard let t0 = firstTap else { return (.tap, listenFrom, deadline, false) }
            return (.tap, t0 + beats[noteIndex], t0 + beats[noteIndex] + tolerance, true)
        case .sleeper:
            // Waits out every stir; searches the next place, then dials the number.
            guard !stirring, outcome == nil, time >= 1 else { return nil }
            if dialing {
                guard dialed.count < code.count, taps < code[dialed.count] else { return nil }
                return (.tap, lastAction + 0.35, .infinity, false)
            }
            guard let i = searched.firstIndex(of: false) else { return nil }
            return (Self.spots[i], lastAction + 1.2, .infinity, false)
        case .lights:
            guard let i = ticks.indices.first(where: { $0 >= 2 && !hit[$0] && ticks[$0] + tolerance > time }) else { return nil }
            return (.tap, ticks[i], ticks[i] + tolerance, true)
        default:
            for rule in rules where !rule.done {
                if case let .require(input, _, _, _) = rule.kind { return (input, rule.from, rule.to, false) }
            }
            return nil
        }
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
                at(t, .haptic(.rush))
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
            at(start + Double(10 - n) * gap, .play(SoundCue(.count(n), pan: rng.range(-0.3, 0.3), behind: true)))
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

    /// How long the pattern is in a round: two moves early in the night, up to five late.
    var echoLength: Int { min(2 + Int((3 * difficulty).rounded()) + echoRound, 6) }
    var echoRounds: Int { difficulty < 0.4 || guided ? 1 : 2 }
    /// The whisper naming each move: early in the night, in practice, and in the Practice Room.
    var echoWhispers: Bool { guided || difficulty < 0.65 }

    /// Every move once, with its note and its whisper: the lesson before the first practice round.
    public static func lesson() -> [(Double, GameEvent)] {
        [Input.left, .right, .up, .down, .tap].enumerated().flatMap { i, move -> [(Double, GameEvent)] in
            let t = Double(i) * 1.6
            return [(t, .play(SoundCue(Sfx.echo(move), pan: echoPan(move)))),
                    (t + 0.45, .play(SoundCue(Sfx.echoSay(move), pan: echoPan(move) * 0.6)))]
        }
    }

    private mutating func startEcho() {
        end = .infinity
        pattern = (0..<echoLength).map { _ in rng.pick(Self.actions) }
        playPattern(from: 0.8)
    }

    private var echoGap: Double { echoWhispers ? 1.1 : 0.8 - 0.25 * difficulty }

    /// Plays the pattern, then the "your turn" chime, then listens.
    private mutating func playPattern(from start: Double) {
        echoIndex = 0
        at(start, .caption(t2("Listen…", "Escute…")))
        for (i, move) in pattern.enumerated() {
            at(start + Double(i) * echoGap, .play(SoundCue(Sfx.echo(move), pan: Self.echoPan(move))))
            if echoWhispers { at(start + Double(i) * echoGap + 0.35, .play(SoundCue(Sfx.echoSay(move), pan: Self.echoPan(move) * 0.6))) }
        }
        let turn = start + Double(pattern.count) * echoGap + 0.2
        at(turn, .play(SoundCue(.echoTurn)))
        at(turn, .caption(t2("Your turn.", "Sua vez.")))
        listenFrom = turn
        deadline = turn + 6
        schedule.sort { $0.time < $1.time }
    }

    private mutating func echoInput(_ input: Input) -> [GameEvent] {
        guard time >= listenFrom - 0.1, echoIndex < pattern.count else { return [] }
        guard input == pattern[echoIndex] else { return echoMistake() }
        echoIndex += 1
        var out: [GameEvent] = [.play(SoundCue(Sfx.echo(input), pan: Self.echoPan(input))), .haptic(.light),
                                .caption(t2("\(echoIndex) of \(pattern.count)", "\(echoIndex) de \(pattern.count)"))]
        deadline = time + 6
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

    // MARK: The Neighbor

    private var neighborRounds: Int { difficulty < 0.5 || guided ? 1 : 2 }

    private mutating func startNeighbor() {
        end = .infinity
        playKnocks(from: 1.0)
    }

    private mutating func playKnocks(from start: Double) {
        knocks = rng.int(2, 3 + Int((3 * difficulty).rounded()))
        taps = 0
        lastTap = -10
        judgeAt = .infinity
        let side = rng.side()
        var t = start
        at(start, .caption(t2("Knock knock…", "Toc toc…")))
        for k in 0..<knocks {
            at(t, .play(SoundCue(.neighborKnock, pan: side.pan * 0.8)))
            // Late at night it knocks with an uneven rhythm, so you have to count, not feel.
            t += k == knocks - 1 ? 0 : 0.6 - 0.15 * difficulty + (difficulty > 0.5 ? rng.range(-0.12, 0.2) : 0)
        }
        listenFrom = t + 0.9
        deadline = listenFrom + 6
        at(listenFrom, .play(SoundCue(.echoTurn)))
        at(listenFrom, .caption(t2("How many? Tap.", "Quantas? Toque.")))
        schedule.sort { $0.time < $1.time }
    }

    private mutating func neighborInput(_ input: Input) -> [GameEvent] {
        guard input == .tap, time >= listenFrom - 0.1 else { return [] }
        taps += 1
        lastTap = time
        judgeAt = time + 1.6
        return [.play(SoundCue(.neighborKnock, volume: 0.5)), .haptic(.light), .caption("\(taps)")]
    }

    private mutating func neighborUpdate() -> [GameEvent] {
        guard listenFrom.isFinite else { return [] }
        if time >= judgeAt || (taps == 0 && time > deadline) {
            listenFrom = .infinity
            if taps == knocks {
                round += 1
                if round >= neighborRounds {
                    outcome = .survived
                    return [.play(SoundCue(.survive)), .caption(t2("Silence. It believes you.", "Silêncio. Ele acreditou."))]
                }
                playKnocks(from: time + 1.2)
                return [.haptic(.success)]
            }
            mistakes += 1
            if mistakes >= 2 {
                outcome = .caught("caught_neighbor")
                return []
            }
            playKnocks(from: time + 1.4)
            return [.play(SoundCue(.echoWrong)), .haptic(.warning),
                    .caption(t2("Wrong. It knocks again. Last try.", "Errado. Ele bate de novo. Última chance."))]
        }
        return []
    }

    // MARK: The Lullaby

    private mutating func startLullaby() {
        end = .infinity
        let notes = 3 + Int((2 * difficulty).rounded())
        var t = 0.0
        beats = [0]
        for _ in 1..<notes {
            t += rng.pick(difficulty < 0.4 ? [0.45, 0.9] : [0.35, 0.6, 0.9])
            beats.append(t)
        }
        pitches = (0..<notes).map { _ in rng.pick([0.84, 0.94, 1.0, 1.12, 1.26]) }
        tolerance = 0.3 - 0.08 * difficulty
        playLullaby(from: 1.0)
    }

    private mutating func playLullaby(from start: Double) {
        firstTap = nil
        noteIndex = 0
        at(start, .caption(t2("Listen to the rhythm…", "Escute o ritmo…")))
        for (b, p) in zip(beats, pitches) { at(start + b, .play(SoundCue(.lullabyNote, rate: p))) }
        listenFrom = start + beats.last! + 1.0
        deadline = listenFrom + 6
        at(listenFrom, .play(SoundCue(.echoTurn)))
        at(listenFrom, .caption(t2("Your turn. Tap the rhythm.", "Sua vez. Toque o ritmo.")))
        schedule.sort { $0.time < $1.time }
    }

    private mutating func lullabyInput(_ input: Input) -> [GameEvent] {
        guard input == .tap, listenFrom.isFinite, time >= listenFrom - 0.1, noteIndex < beats.count else { return [] }
        if let t0 = firstTap {
            let expected = t0 + beats[noteIndex]
            guard abs(time - expected) <= tolerance else { return lullabyMistake() }
        } else {
            firstTap = time
        }
        let note: [GameEvent] = [.play(SoundCue(.lullabyNote, rate: pitches[noteIndex])), .haptic(.light)]
        noteIndex += 1
        if noteIndex == beats.count {
            outcome = .survived
            return note + [.caption(t2("It falls asleep.", "Ela adormeceu."))]
        }
        return note
    }

    private mutating func lullabyUpdate() -> [GameEvent] {
        guard listenFrom.isFinite else { return [] }
        if let t0 = firstTap, noteIndex < beats.count, time > t0 + beats[noteIndex] + tolerance { return lullabyMistake() }
        if firstTap == nil, time > deadline { return lullabyMistake() }
        return []
    }

    private mutating func lullabyMistake() -> [GameEvent] {
        mistakes += 1
        listenFrom = .infinity
        if mistakes >= 2 {
            outcome = .caught("caught_lullaby")
            return []
        }
        playLullaby(from: time + 1.4)
        return [.play(SoundCue(.echoWrong)), .haptic(.warning),
                .caption(t2("Off the beat. Once more.", "Fora do ritmo. Mais uma vez."))]
    }

    // MARK: The Breather

    private mutating func buildBreather() {
        let d = difficulty
        let rounds = 2 + (d > 0.5 ? 1 : 0)
        let window = 1.5 - 0.5 * d
        let circle: [Double] = [-1, -0.6, 0, 0.6, 1, 0.6, 0, -0.6]
        var t = 0.8
        var start = rng.int(0, circle.count - 1)
        at(t, .caption(t2("Breathing… all around you.", "Respiração… em volta de você.")))
        for _ in 0..<rounds {
            let breaths = rng.int(4, 6)
            for k in 0..<breaths {
                t += 0.75 - 0.15 * d
                let spot = (start + k) % circle.count
                // The second half of the circle is behind you.
                at(t, .play(SoundCue(.breath, pan: circle[spot], volume: 0.3 + 0.5 * Double(k) / Double(breaths), behind: spot > 4)))
            }
            start += breaths
            t += 0.6
            let side = rng.side()
            at(t, .play(SoundCue(.breathClose, pan: side == .left ? -1 : 1)))
            at(t, .haptic(.rush))
            at(t, .caption(side == .left ? t2("In your LEFT ear!", "No ouvido ESQUERDO!") : t2("In your RIGHT ear!", "No ouvido DIREITO!")))
            let toward: Input = side == .left ? .left : .right
            let away: Input = side == .left ? .right : .left
            rules.append(Rule(from: t - 0.05, to: t + window,
                              kind: .require(toward, wrong: [away], ends: false,
                                             success: [.play(SoundCue(.shove, pan: side.pan * 0.6)), .haptic(.success)]),
                              reason: "caught_breather"))
            t += window + 0.4
        }
        end = t
    }

    // MARK: The Twins

    private mutating func buildTwins() {
        let d = difficulty
        let rounds = 2 + (d > 0.5 ? 1 : 0)
        let window = 2.0 - 0.6 * d
        let gap = 0.45 - 0.25 * d
        var t = 1.0
        at(0.4, .caption(t2("Two voices. The first one tells the truth.", "Duas vozes. A primeira fala a verdade.")))
        for _ in 0..<rounds {
            t += rng.range(0.8, 1.4)
            let realSide = rng.side(), says = rng.side()
            let realWord: Sfx = says == .left ? .twinLeft : .twinRight
            let lieWord: Sfx = says == .left ? .twinRight : .twinLeft
            at(t, .play(SoundCue(realWord, pan: realSide == .left ? -1 : 1)))
            at(t + gap, .play(SoundCue(lieWord, pan: realSide == .left ? 1 : -1)))
            let right: Input = says == .left ? .left : .right
            let wrong: Input = says == .left ? .right : .left
            rules.append(Rule(from: t, to: t + gap + window,
                              kind: .require(right, wrong: [wrong], ends: false, success: [.haptic(.light)]),
                              reason: "caught_twins"))
            t += gap + window
        }
        end = t + 0.3
        at(end - 0.1, .play(SoundCue(.survive)))
    }

    // MARK: The Lights

    private mutating func buildLights() {
        let d = difficulty
        let count = 6 + Int((3 * d).rounded())
        let interval = 0.85 - 0.25 * d
        tolerance = 0.24 - 0.06 * d
        at(0.2, .play(SoundCue(.lightsOff)))
        at(0.2, .caption(t2("The power goes out. Tick… tock…", "A luz acaba. Tique… taque…")))
        ticks = (0..<count).map { 1.4 + Double($0) * interval }
        hit = Array(repeating: false, count: count)
        for (i, t) in ticks.enumerated() { at(t, .play(SoundCue(.tick, volume: i < 2 ? 0.7 : 1))) }
        end = ticks.last! + tolerance + 0.2
    }

    private mutating func lightsInput(_ input: Input) -> [GameEvent] {
        guard input == .tap, time > ticks[0] - 0.3 else { return [] }
        if let i = ticks.indices.first(where: { $0 >= 2 && !hit[$0] && abs(time - ticks[$0]) <= tolerance }) {
            hit[i] = true
            return [.haptic(.light)]
        }
        // A tap during the first two ticks (listening) is fine; off the beat later is a mistake.
        if time < ticks[1] + tolerance { return [] }
        return lightsMistake()
    }

    private mutating func lightsUpdate() -> [GameEvent] {
        var out: [GameEvent] = []
        for i in ticks.indices where i >= 2 && !hit[i] && time > ticks[i] + tolerance {
            hit[i] = true   // counted once, as a miss
            out += lightsMistake()
            if outcome != nil { return out }
        }
        if time >= end, outcome == nil {
            outcome = .survived
            out += [.play(SoundCue(.lightsOn)), .caption(t2("The lights come back on.", "As luzes voltam."))]
        }
        return out
    }

    private mutating func lightsMistake() -> [GameEvent] {
        mistakes += 1
        if mistakes >= 2 {
            outcome = .caught("caught_lights")
            return []
        }
        return [.play(SoundCue(.echoWrong, volume: 0.6)), .haptic(.warning),
                .caption(t2("The lights flicker. One more miss…", "As luzes piscam. Mais um erro…"))]
    }

    // MARK: The Sleeper

    /// Mistakes allowed before it wakes: one (two while practicing).
    private var sleeperMistakes: Int { guided ? 3 : 2 }
    var stirring: Bool { time >= stirFrom && time < stirTo }

    private mutating func startSleeper() {
        let d = difficulty
        end = .infinity
        needed = guided || d < 0.4 ? 2 : 3
        // Hide the numbers in different places; the rest are empty.
        var places = [0, 1, 2, 3]
        hidden = [0, 0, 0, 0]
        for _ in 0..<needed {
            hidden[places.remove(at: rng.int(0, places.count - 1))] = rng.int(1, 6)
        }
        at(0, .music(.sleeper))
        at(0.3, .caption(t2("Snoring. Search while it sleeps. Freeze when it stops.", "Roncos. Procure enquanto ele dorme. Congele quando parar.")))
        nextSnore = 0.8
        nextStir = guided ? 9 : rng.range(5.5, 8)
        // It wakes up on its own eventually.
        wakeAt = 100
    }

    private func pan(_ spot: Input) -> (Double, Bool) {
        switch spot {
        case .left: return (-0.8, false)
        case .right: return (0.8, false)
        case .down: return (0, true)   // behind you
        default: return (0, false)     // in front of you
        }
    }

    /// A sound you made while it was awake (a small grace moment as it starts stirring).
    private mutating func sleeperNoise() -> [GameEvent] {
        mistakes += 1
        if mistakes >= sleeperMistakes {
            outcome = .caught("caught_sleeper")
            return []
        }
        return [.play(SoundCue(.sleeperStir, volume: 1)), .haptic(.warning),
                .caption(t2("It heard you. One more sound and it wakes up.", "Ele ouviu. Mais um barulho e ele acorda."))]
    }

    private mutating func sleeperInput(_ input: Input) -> [GameEvent] {
        guard time > 0.6 else { return [] }
        if stirring && time > stirFrom + 0.35 { lastAction = time; return sleeperNoise() }
        lastAction = time
        if dialing {
            guard input == .tap else { return [] }
            taps += 1
            judgeAt = time + 1.5
            return [.play(SoundCue(.dialClick)), .haptic(.light), .caption("\(taps)")]
        }
        if input == .tap {
            // Whispers the numbers found so far.
            guard !code.isEmpty else {
                return [.caption(t2("No numbers yet. Swipe to search.", "Nenhum número ainda. Deslize para procurar."))]
            }
            var out: [GameEvent] = [.caption(code.map(String.init).joined(separator: " "))]
            for (k, n) in code.enumerated() { at(time + 0.1 + 0.8 * Double(k), .play(SoundCue(.num(n), volume: 0.8))) }
            schedule.sort { $0.time < $1.time }
            out.append(.haptic(.light))
            return out
        }
        guard let i = Self.spots.firstIndex(of: input) else { return [] }
        let (p, behind) = pan(input)
        var out: [GameEvent] = [.play(SoundCue(.search, pan: p, volume: 0.6, behind: behind)), .haptic(.light)]
        guard !searched[i] else {
            return out + [.caption(t2("Already searched.", "Já procurou aí."))]
        }
        let n = hidden[i]
        searched[i] = true
        guard n > 0 else { return out + [.caption(t2("Nothing.", "Nada."))] }
        code.append(n)
        out += [.play(SoundCue(.noteFound, pan: p, volume: 0.7, behind: behind)),
                .caption(t2("A note: \(n)", "Um bilhete: \(n)"))]
        at(time + 0.6, .play(SoundCue(.num(n), pan: p * 0.5, volume: 0.9, behind: behind)))
        if code.count == needed {
            // The Host tells you it's time for the phone. It stays asleep while the Host talks.
            dialing = true
            taps = 0
            at(time + 1.6, .say("sleeper_dial"))
            nextStir = max(nextStir, time + 9)
        }
        schedule.sort { $0.time < $1.time }
        return out
    }

    private mutating func sleeperUpdate() -> [GameEvent] {
        var out: [GameEvent] = []
        if time >= wakeAt {
            outcome = .caught("caught_sleeper")
            return out
        }
        // Stirring: the snoring stops. Then it settles and snores again.
        if !stirring, time >= nextStir, stirTo.isInfinite || time >= stirTo {
            stirFrom = time
            stirTo = time + (guided ? 3.5 : rng.range(2.5, 3.5 + difficulty))
            nextStir = stirTo + rng.range(5, 9) - 2 * difficulty
            out += [.play(SoundCue(.sleeperStir, pan: 0.2, volume: 0.8)), .haptic(.heartbeat),
                    .caption(t2("The snoring stops. Freeze!", "O ronco parou. Congele!"))]
        } else if stirTo.isFinite, time >= stirTo {
            stirFrom = .infinity
            stirTo = .infinity
            nextSnore = time
            // In the middle of a number: you get time to finish it.
            if dialing, taps > 0 { judgeAt = max(judgeAt, time + 1.5) }
            out.append(.caption(t2("Snoring again.", "Roncando de novo.")))
        }
        if !stirring, time >= nextSnore {
            out.append(.play(SoundCue(.snore, pan: 0.2, volume: 0.75)))
            nextSnore = time + 2.6
        }
        // Each number is dialed when you stop tapping.
        // The phone waits while you're frozen.
        if dialing, time >= judgeAt, !stirring {
            judgeAt = .infinity
            let want = code[dialed.count]
            if taps == want {
                dialed.append(taps)
                out += [.play(SoundCue(.dialReturn, volume: 0.6)), .caption(t2("Dialed \(taps).", "Discou \(taps)."))]
                // A whisper of the number you just dialed.
                at(time + 0.7, .play(SoundCue(.num(taps), volume: 0.8)))
                schedule.sort { $0.time < $1.time }
                taps = 0
                if dialed.count == code.count {
                    outcome = .survived
                    out += [.play(SoundCue(.unlock)), .caption(t2("The front desk answers. The lock clicks open. Tiptoe out.",
                                                                     "A recepção atende. A tranca abre. Saia na ponta dos pés."))]
                }
            } else {
                dialed = []
                taps = 0
                out.append(.play(SoundCue(.dialReturn, volume: 0.6)))
                out += sleeperNoise()
                if outcome == nil {
                    out.append(.caption(t2("Wrong number. Dial again from the first number.", "Número errado. Disque de novo desde o primeiro número.")))
                }
            }
        }
        return out
    }
}
