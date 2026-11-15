/// Everything in the hallway: sides, items, rooms, creatures, and the names of every sound the game plays.

public enum Side: String, Codable, CaseIterable, Sendable {
    case left, right

    public var opposite: Side { self == .left ? .right : .left }
    /// Where the sound sits, -1 (far left) to 1 (far right).
    public var pan: Double { self == .left ? -0.85 : 0.85 }
}

public enum Item: String, Codable, CaseIterable, Sendable, Comparable {
    case lighter, bandage, charm

    public var name: String {
        switch self {
        case .lighter: return "Lighter"
        case .bandage: return "Bandage"
        case .charm: return "Lucky Charm"
        }
    }

    public var price: Int {
        switch self {
        case .lighter: return 2
        case .bandage: return 4
        case .charm: return 10
        }
    }

    public var about: String {
        switch self {
        case .lighter: return "Peek under both doors. The Host tells you the truth about what's behind them."
        case .bandage: return "Get one heart back."
        case .charm: return "The next time something gets you, the charm breaks instead of you."
        }
    }

    public static func < (a: Item, b: Item) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
}

public enum Creature: String, Codable, CaseIterable, Sendable {
    case drip, staticBuzz = "static", crawler, counter, mimic

    public var name: String {
        switch self {
        case .drip: return "The Drip"
        case .staticBuzz: return "Static"
        case .crawler: return "The Crawler"
        case .counter: return "The Counter"
        case .mimic: return "The Mimic"
        }
    }

    /// The first hour it can show up.
    public var firstHour: Int {
        switch self {
        case .drip, .staticBuzz: return 1
        case .crawler: return 3
        case .counter: return 5
        case .mimic: return 4
        }
    }

    /// How to survive it, for How to Play.
    public var howTo: String {
        switch self {
        case .drip:
            return "Drips speed up as it comes closer. When you hear the big splash, swipe down to hide in the locker. Hide too early and it hears the locker door."
        case .staticBuzz:
            return "A buzz appears on your left or your right. Swipe the other way, away from it. It comes back a few times, faster each time."
        case .crawler:
            return "Footsteps creep up behind you. If it growls, swipe up to run. If it stops and sniffs, don't touch anything until it walks away. Run too soon and it chases you."
        case .counter:
            return "It counts down from ten. Don't touch the screen at all until it sighs and leaves. Later on it tries to trick you with noises."
        case .mimic:
            return "It hides behind doors pretending to be a good room, but its sound is a little too low. Inside, it plays a sound on both sides. One is real and one is the Mimic, lower. Swipe toward the real one. Tap to hear them again."
        }
    }
}

public enum SafeRoom: String, Codable, CaseIterable, Sendable {
    case bedroom, kitchen, vault, storage, empty

    public var name: String {
        switch self {
        case .bedroom: return "Bedroom"
        case .kitchen: return "Kitchen"
        case .vault: return "Vault"
        case .storage: return "Storage closet"
        case .empty: return "Empty room"
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

    /// What its hint sounds like, for How to Play and captions.
    public var hintDescription: String {
        switch self {
        case .bedroom: return "a soft bell"
        case .kitchen: return "dishes clinking"
        case .vault: return "keys jingling"
        case .storage: return "a wooden box opening"
        case .empty: return "a quiet breeze"
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
public enum Sfx: String, Codable, CaseIterable, Sendable {
    // Hints through the doors
    case hintBedroom = "hint_bedroom", hintKitchen = "hint_kitchen", hintVault = "hint_vault"
    case hintStorage = "hint_storage", hintEmpty = "hint_empty"
    case hintDrip = "hint_drip", hintStatic = "hint_static", hintCrawler = "hint_crawler", hintCounter = "hint_counter"
    // Doors and you
    case doorOpen = "door_open", doorClose = "door_close", locker = "locker", runAway = "run_away"
    // Rooms
    case heal = "heal", coins = "coins", itemGet = "item_get", nothing = "nothing"
    // The Drip
    case drip1 = "drip1", drip2 = "drip2", drip3 = "drip3", splash = "splash"
    // Static
    case buzz = "buzz", zapOut = "zap_out"
    // The Crawler
    case crawl1 = "crawl1", crawl2 = "crawl2", crawl3 = "crawl3", growl = "growl", sniff = "sniff"
    // The Counter (its voice) and its tricks
    case count1 = "count1", count2 = "count2", count3 = "count3", count4 = "count4", count5 = "count5"
    case count6 = "count6", count7 = "count7", count8 = "count8", count9 = "count9", count10 = "count10"
    case counterSigh = "counter_sigh", decoyKnock = "decoy_knock", decoyCreak = "decoy_creak"
    // The Mimic
    case mimicVoice1 = "mimic_voice1", mimicVoice2 = "mimic_voice2", mimicVoice3 = "mimic_voice3"
    // Results
    case hit = "hit", charmBreak = "charm_break", survive = "survive", heartbeat = "heartbeat"
    case loseSting = "lose_sting", winSting = "win_sting"

    public static func count(_ n: Int) -> Sfx {
        [.count1, .count2, .count3, .count4, .count5, .count6, .count7, .count8, .count9, .count10][n - 1]
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
}

/// A sound to play now.
public struct SoundCue: Equatable, Sendable {
    public var sfx: Sfx
    public var pan: Double
    public var volume: Double
    public var rate: Double
    /// Heard through a closed door: quieter and dull.
    public var muffled: Bool

    public init(_ sfx: Sfx, pan: Double = 0, volume: Double = 1, rate: Double = 1, muffled: Bool = false) {
        self.sfx = sfx
        self.pan = pan
        self.volume = volume
        self.rate = rate
        self.muffled = muffled
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
}
