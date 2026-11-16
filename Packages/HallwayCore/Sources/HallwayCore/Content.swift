/// Everything in the hallway: sides, items, rooms, creatures, and the names of every sound the game plays.
/// Text the player sees comes in English and Brazilian Portuguese.

public enum Language: String, Codable, CaseIterable, Sendable {
    case en, pt

    public var name: String { self == .en ? "English" : "Português (Brasil)" }

    /// Picks the text for this language.
    public func t(_ en: String, _ pt: String) -> String { self == .en ? en : pt }
}

public enum Side: String, Codable, CaseIterable, Sendable {
    case left, right

    public var opposite: Side { self == .left ? .right : .left }
    /// Where the sound sits, -1 (far left) to 1 (far right).
    public var pan: Double { self == .left ? -0.85 : 0.85 }
}

public enum Item: String, Codable, CaseIterable, Sendable, Comparable {
    case lighter, bandage, earplugs, coin, key, charm, secondChance

    public func name(_ l: Language) -> String {
        switch self {
        case .lighter: return l.t("Lighter", "Isqueiro")
        case .bandage: return l.t("Bandage", "Curativo")
        case .earplugs: return l.t("Earplugs", "Protetor de ouvido")
        case .coin: return l.t("Lucky Coin", "Moeda da Sorte")
        case .key: return l.t("Skeleton Key", "Chave Mestra")
        case .charm: return l.t("Lucky Charm", "Amuleto")
        case .secondChance: return l.t("Second Chance", "Segunda Chance")
        }
    }

    public var price: Int {
        switch self {
        case .lighter: return 2
        case .bandage: return 4
        case .earplugs: return 4
        case .coin: return 5
        case .key: return 6
        case .charm: return 8
        case .secondChance: return 14
        }
    }

    public func about(_ l: Language) -> String {
        switch self {
        case .lighter: return l.t("Peek under both doors. The Host tells you the truth about what's behind them.",
                                  "Espie embaixo das duas portas. O apresentador conta a verdade sobre o que tem atrás delas.")
        case .bandage: return l.t("Get one heart back.", "Recupera um coração.")
        case .earplugs: return l.t("The next time you meet the Counter, you can't hear it count, so it can't trick you. It leaves.",
                                   "Na próxima vez que encontrar o Contador, você não ouve a contagem, então ele não te engana. Ele vai embora.")
        case .coin: return l.t("Double tokens for the next nine doors.", "Fichas em dobro nas próximas nove portas.")
        case .key: return l.t("Skip a pair of doors. You walk straight past them to the next ones.",
                              "Pule um par de portas. Você passa direto por elas até as próximas.")
        case .charm: return l.t("The next time something gets you, the charm breaks instead of you.",
                                "Na próxima vez que algo te pegar, o amuleto quebra no seu lugar.")
        case .secondChance: return l.t("If you lose your last heart, you get one back instead of losing the night. Works once.",
                                       "Se você perder o último coração, ganha um de volta em vez de perder a noite. Funciona uma vez.")
        }
    }

    /// Used from the hallway (the others work by themselves).
    public var usable: Bool { [.lighter, .bandage, .coin, .key].contains(self) }

    public static func < (a: Item, b: Item) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
}

public enum Creature: String, Codable, CaseIterable, Sendable {
    case drip, staticBuzz = "static", crawler, counter, mimic
    /// Not really a creature: a music-box puzzle. Play its pattern back.
    case echo
    case neighbor, lullaby, breather, twins, lights

    public func name(_ l: Language) -> String {
        switch self {
        case .drip: return l.t("The Drip", "A Goteira")
        case .staticBuzz: return l.t("Static", "Estática")
        case .crawler: return l.t("The Crawler", "O Rastejante")
        case .counter: return l.t("The Counter", "O Contador")
        case .mimic: return l.t("The Mimic", "O Imitador")
        case .echo: return l.t("The Echo", "O Eco")
        case .neighbor: return l.t("The Neighbor", "O Vizinho")
        case .lullaby: return l.t("The Lullaby", "A Canção de Ninar")
        case .breather: return l.t("The Breather", "O Respirador")
        case .twins: return l.t("The Twins", "As Gêmeas")
        case .lights: return l.t("The Lights", "As Luzes")
        }
    }

    /// The first hour it can show up.
    public var firstHour: Int {
        switch self {
        case .drip, .staticBuzz: return 1
        case .echo: return 2
        case .crawler: return 3
        case .mimic: return 4
        case .counter: return 5
        case .neighbor: return 6
        case .lullaby: return 8
        case .breather: return 10
        case .twins: return 14
        case .lights: return 16
        }
    }

    /// The creatures behind creature doors (the Echo has doors of its own).
    public static let monsters: [Creature] = [.drip, .staticBuzz, .crawler, .counter, .mimic,
                                              .neighbor, .lullaby, .breather, .twins, .lights]

    /// How to survive it, for How to Play and the Practice Room.
    public func howTo(_ l: Language) -> String {
        switch self {
        case .drip:
            return l.t("Drips speed up as it comes closer. When you hear the big splash, swipe down to hide in the locker. Hide too early and it hears the locker door.",
                       "As gotas aceleram conforme ela chega perto. Quando ouvir o splash, deslize para baixo para se esconder no armário. Cedo demais e ela ouve a porta do armário.")
        case .staticBuzz:
            return l.t("A buzz plays in one ear. Swipe the other way, away from it. Each right swipe makes a zap. It comes back three to five times, faster each time, until you hear it fizzle out.",
                       "Um zumbido toca em um ouvido. Deslize para o outro lado, para longe dele. Cada acerto faz um zap. Ele volta de três a cinco vezes, cada vez mais rápido, até sumir com um chiado.")
        case .crawler:
            return l.t("Footsteps creep up behind you. If it growls, swipe up and run. If it stops and sniffs, don't touch anything until it walks away. Run too soon and it chases you.",
                       "Passos se aproximam por trás. Se ele rosnar, deslize para cima e corra. Se ele parar e farejar, não toque em nada até ele ir embora. Correr cedo demais faz ele te perseguir.")
        case .counter:
            return l.t("It counts down from ten. Don't touch the screen at all until it sighs and leaves. Later on it tries to trick you with noises.",
                       "Ele conta de dez até um. Não toque na tela até ele suspirar e ir embora. Mais tarde ele tenta te enganar com barulhos.")
        case .mimic:
            return l.t("It hides behind doors pretending to be a good room, but its sound is a little too low. Inside, it plays a voice on both sides. One is real and one is the Mimic, lower. Swipe toward the real one. Tap to hear them again.",
                       "Ele se esconde atrás das portas fingindo ser um quarto bom, mas o som dele é um pouco grave demais. Lá dentro, uma voz toca dos dois lados. Uma é real e a outra é o Imitador, mais grave. Deslize para o lado da voz real. Toque para ouvir de novo.")
        case .echo:
            return l.t("A music box. It plays a short pattern of notes, and a whisper names each one: left, right, up, down, or knock. Then it chimes: your turn. Play the pattern back: swipe left, right, up or down, and tap for the knock. You have six seconds for each move, and three mistakes before it shrieks. Late at night the whispers stop and only the notes play. Solve it for lots of tokens.",
                       "Uma caixinha de música. Ela toca uma sequência curta de notas, e um sussurro diz o nome de cada uma: esquerda, direita, cima, baixo ou batida. Depois toca um sino: sua vez. Repita a sequência: deslize para esquerda, direita, cima ou baixo, e toque para a batida. Você tem seis segundos para cada movimento e três erros antes de ela gritar. Tarde da noite os sussurros param e só as notas tocam. Resolva e ganhe muitas fichas.")
        case .neighbor:
            return l.t("It knocks on the wall, two to six times. Count the knocks. When the chime plays, tap the screen the same number of times. Get it wrong and it knocks again; get it wrong twice and it comes through the wall.",
                       "Ele bate na parede, de duas a seis vezes. Conte as batidas. Quando o sino tocar, toque na tela o mesmo número de vezes. Errou, ele bate de novo; errou duas vezes, ele atravessa a parede.")
        case .lullaby:
            return l.t("It hums a few notes. Listen to the rhythm: when each note comes. When the chime plays, tap the same rhythm back, one tap for each note. The pitch doesn't matter, only the timing. Two tries.",
                       "Ela cantarola algumas notas. Escute o ritmo: quando cada nota vem. Quando o sino tocar, toque o mesmo ritmo, um toque para cada nota. O tom não importa, só o tempo. Duas tentativas.")
        case .breather:
            return l.t("It circles around you, breathing closer and closer. When it stops and breathes right into one of your ears, swipe toward that ear to shove it away. It comes back two or three times.",
                       "Ele anda em volta de você, respirando cada vez mais perto. Quando ele para e respira bem dentro de um dos seus ouvidos, deslize para o lado desse ouvido para empurrá-lo. Ele volta duas ou três vezes.")
        case .twins:
            return l.t("Two voices, one in each ear, say left and right at almost the same time. One of them lies. The real one always speaks first: swipe the way it tells you. Later in the night they speak closer together.",
                       "Duas vozes, uma em cada ouvido, dizem esquerda e direita quase ao mesmo tempo. Uma delas mente. A verdadeira sempre fala primeiro: deslize para o lado que ela disser. Mais tarde na noite elas falam mais juntas.")
        case .lights:
            return l.t("The power goes out and a clock starts ticking. Listen to the first two ticks, then tap the screen on every tick to keep the lights on. Miss two ticks, or tap off the beat twice, and the lights go out for good.",
                       "A luz acaba e um relógio começa a tiquetaquear. Escute os dois primeiros tiques, depois toque na tela em cada tique para manter as luzes acesas. Perca dois tiques, ou toque fora do ritmo duas vezes, e as luzes apagam de vez.")
        }
    }
}

public enum SafeRoom: String, Codable, CaseIterable, Sendable {
    case bedroom, kitchen, vault, storage, empty

    public func name(_ l: Language) -> String {
        switch self {
        case .bedroom: return l.t("Bedroom", "Quarto")
        case .kitchen: return l.t("Kitchen", "Cozinha")
        case .vault: return l.t("Vault", "Cofre")
        case .storage: return l.t("Storage closet", "Depósito")
        case .empty: return l.t("Empty room", "Sala vazia")
        }
    }

    public var hint: Sfx {
        switch self {
        case .bedroom: return .hintBedroom
        case .kitchen: return .hintKitchen
        case .vault: return .hintVault
        case .storage: return .hintStorage
        case .empty: return .hintEmpty
        }
    }

    /// What its hint sounds like, for How to Play.
    public func hintDescription(_ l: Language) -> String {
        switch self {
        case .bedroom: return l.t("a soft bell", "um sino suave")
        case .kitchen: return l.t("dishes clinking", "pratos batendo")
        case .vault: return l.t("keys jingling", "chaves balançando")
        case .storage: return l.t("a wooden box opening", "uma caixa de madeira abrindo")
        case .empty: return l.t("a quiet breeze", "uma brisa leve")
        }
    }

    public func effect(_ l: Language) -> String {
        switch self {
        case .bedroom: return l.t("Gives you a heart back.", "Devolve um coração.")
        case .kitchen: return l.t("Has a bandage.", "Tem um curativo.")
        case .vault: return l.t("Has tokens.", "Tem fichas.")
        case .storage: return l.t("Has a random item.", "Tem um item surpresa.")
        case .empty: return l.t("Nothing happens. That's good.", "Nada acontece. Isso é bom.")
        }
    }
}

public enum Room: Codable, Hashable, Sendable {
    case safe(SafeRoom)
    case creature(Creature)

    public var isSafe: Bool { if case .safe = self { return true }; return false }

    public var key: String {
        switch self {
        case let .safe(r): return r.rawValue
        case let .creature(c): return c.rawValue
        }
    }
}

/// One door in the hallway: what's behind it, and the sound you hear through it.
public struct Door: Codable, Hashable, Sendable {
    public var room: Room
    public var hint: Sfx
    /// Playback speed of the hint. Below 1 sounds lower: that's the Mimic pretending.
    public var rate: Double

    public init(room: Room, hint: Sfx, rate: Double = 1) {
        self.room = room
        self.hint = hint
        self.rate = rate
    }
}

/// Every one-shot sound. The raw value is the file name in the app (sfx_<raw>.m4a).
/// Spoken ones (the Counter's numbers, the Mimic's voices) also have a Portuguese file (sfx_pt_<raw>.m4a).
public enum Sfx: String, Codable, CaseIterable, Sendable {
    // Hints through the doors
    case hintBedroom = "hint_bedroom", hintKitchen = "hint_kitchen", hintVault = "hint_vault"
    case hintStorage = "hint_storage", hintEmpty = "hint_empty"
    case hintDrip = "hint_drip", hintStatic = "hint_static", hintCrawler = "hint_crawler", hintCounter = "hint_counter"
    case hintEcho = "hint_echo"
    // Doors and you
    case doorOpen = "door_open", doorClose = "door_close", locker = "locker", runAway = "run_away"
    // Rooms
    case heal = "heal", coins = "coins", itemGet = "item_get", nothing = "nothing"
    // The Drip
    case drip1 = "drip1", drip2 = "drip2", drip3 = "drip3", splash = "splash"
    // Static
    case buzz = "buzz", zap = "zap", zapOut = "zap_out"
    // The Crawler
    case crawl1 = "crawl1", crawl2 = "crawl2", crawl3 = "crawl3", growl = "growl", sniff = "sniff"
    // The Counter (its voice) and its tricks
    case count1 = "count1", count2 = "count2", count3 = "count3", count4 = "count4", count5 = "count5"
    case count6 = "count6", count7 = "count7", count8 = "count8", count9 = "count9", count10 = "count10"
    case counterSigh = "counter_sigh", decoyKnock = "decoy_knock", decoyCreak = "decoy_creak"
    // The Mimic
    case mimicVoice1 = "mimic_voice1", mimicVoice2 = "mimic_voice2", mimicVoice3 = "mimic_voice3"
    // The Echo
    case echoLeft = "echo_left", echoRight = "echo_right", echoUp = "echo_up", echoDown = "echo_down", echoTap = "echo_tap"
    case echoTurn = "echo_turn", echoWrong = "echo_wrong", echoSolved = "echo_solved"
    /// A whisper naming each Echo move ("left", "up", "knock"…), so you don't have to learn the notes first.
    case echoSayLeft = "echo_say_left", echoSayRight = "echo_say_right", echoSayUp = "echo_say_up"
    case echoSayDown = "echo_say_down", echoSayTap = "echo_say_tap"
    // The Neighbor, the Lullaby, the Breather, the Twins and the Lights
    case hintNeighbor = "hint_neighbor", neighborKnock = "neighbor_knock"
    case hintLullaby = "hint_lullaby", lullabyNote = "lullaby_note"
    case hintBreather = "hint_breather", breath = "breath", breathClose = "breath_close", shove = "shove"
    case hintTwins = "hint_twins", twinLeft = "twin_left", twinRight = "twin_right"
    case hintLights = "hint_lights", tick = "tick", lightsOff = "lights_off", lightsOn = "lights_on"
    // Results
    case hit = "hit", charmBreak = "charm_break", survive = "survive", heartbeat = "heartbeat"
    case loseSting = "lose_sting", winSting = "win_sting"

    public static func count(_ n: Int) -> Sfx {
        [.count1, .count2, .count3, .count4, .count5, .count6, .count7, .count8, .count9, .count10][n - 1]
    }

    /// Spoken sounds have one recording per language.
    public var spoken: Bool {
        (rawValue.hasPrefix("count") && !rawValue.hasPrefix("counter"))
            || ["mimic_voice", "echo_say", "twin_", "hint_twins"].contains { rawValue.hasPrefix($0) }
    }

    /// The sound the Echo makes for a move.
    public static func echo(_ input: Input) -> Sfx {
        switch input {
        case .left: return .echoLeft
        case .right: return .echoRight
        case .up: return .echoUp
        case .down: return .echoDown
        default: return .echoTap
        }
    }

    /// The whisper that names an Echo move.
    public static func echoSay(_ input: Input) -> Sfx {
        switch input {
        case .left: return .echoSayLeft
        case .right: return .echoSayRight
        case .up: return .echoSayUp
        case .down: return .echoSayDown
        default: return .echoSayTap
        }
    }
}

/// Background loops.
public enum Ambience: String, Codable, CaseIterable, Sendable {
    case hallway = "amb_hallway", deep = "amb_deep", room = "amb_room", shop = "amb_shop"
}

/// Music. It always fades out when a creature shows up, so you can hear it clearly.
public enum Track: String, Codable, CaseIterable, Sendable {
    case menu = "mus_menu", early = "mus_early", middle = "mus_middle", late = "mus_late"
    case calm = "mus_calm", win = "mus_win", lose = "mus_lose"
}

public enum Haptic: String, Codable, Sendable {
    case light, heavy, warning, success, heartbeat
    /// A creature lunges at you (the Crawler's growl, the Breather in your ear).
    case rush
    /// You were caught.
    case hit
}

/// A sound to play now.
public struct SoundCue: Equatable, Sendable {
    public var sfx: Sfx
    public var pan: Double
    public var volume: Double
    public var rate: Double
    /// Heard through a closed door: quieter and dull.
    public var muffled: Bool
    /// Behind you rather than in front (only heard as such with headphones and 3D sound).
    /// Left and right stay the same, so the game plays the same either way.
    public var behind: Bool

    public init(_ sfx: Sfx, pan: Double = 0, volume: Double = 1, rate: Double = 1, muffled: Bool = false, behind: Bool = false) {
        self.sfx = sfx
        self.pan = pan
        self.volume = volume
        self.rate = rate
        self.muffled = muffled
        self.behind = behind
    }
}

/// What the player does. On the phone: swipes and taps on the play area, or buttons.
public enum Input: Equatable, Sendable {
    case left, right, up, down, tap
    case listen
    case use(Item)
    case buy(Item)
    case leave
    /// Skip what the Host is saying.
    case skip
    /// Practice Room: try the same challenge again.
    case again
}
