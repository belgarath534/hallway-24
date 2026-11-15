/// Everything the Host says. Two Hosts, same game, different personalities:
/// Lewis is a polite, old-fashioned gentleman; Heart is far too sweet.
///
/// Every line has an id. The app plays the recording v_<host>_<id>.m4a when there is one, and otherwise
/// speaks the text. `tools/make_voices.py` records every line (the list comes from the DumpScript test).
public enum Host: String, Codable, CaseIterable, Sendable {
    case lewis, heart

    public var name: String { self == .lewis ? "Lewis" : "Heart" }

    public var about: String {
        self == .lewis
            ? "A polite gentleman with a British accent. Very proper. Very calm. Slightly too calm."
            : "A sweet, cheerful woman. She's so proud of you. Even when you pick the wrong door."
    }
}

public enum HostScript {
    public struct Line: Sendable {
        public let id: String
        public let lewis: String
        public let heart: String

        public func text(_ host: Host) -> String { host == .lewis ? lewis : heart }
    }

    public static func text(_ id: String, _ host: Host) -> String { byID[id]?.text(host) ?? id }

    public static func has(_ id: String) -> Bool { byID[id] != nil }

    /// Ids of the variants of a line: "doors" gives doors_1, doors_2, …
    public static func variants(_ prefix: String) -> [String] {
        lines.map(\.id).filter { $0.hasPrefix(prefix + "_") && Int($0.dropFirst(prefix.count + 1)) != nil }
    }

    static let byID: [String: Line] = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) })

    private static func l(_ id: String, _ lewis: String, _ heart: String) -> Line { Line(id: id, lewis: lewis, heart: heart) }

    private static let numbers = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
                                  "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
                                  "nineteen", "twenty", "twenty one", "twenty two", "twenty three", "twenty four"]

    public static let lines: [Line] = intro + hours + doors + rooms + lighter + creatures + results + shop + items + flavor

    static let intro: [Line] = [
        l("intro_1",
          "Good evening, and welcome to Hallway twenty four. I'm Lewis, your host. The rules are simple. Stay for twenty four hours. Every hour, you choose a door.",
          "Hi! Welcome to Hallway twenty four! I'm Heart, your host, and I'm so happy you're here. Stay with me for twenty four hours. Every hour, you pick a door!"),
        l("intro_2",
          "Before you choose, listen. Each door makes a sound. Bells, keys and dishes are usually lovely. Dripping, buzzing and scratching… usually are not.",
          "Listen first, okay? Every door makes a little sound. Bells, keys and dishes are nice rooms. Dripping, buzzing and scratching are… less nice."),
        l("intro_3",
          "Choose the left door or the right door. Listen again whenever you like. If something finds you, I'll tell you what to do. Once. Do try to keep up.",
          "Pick left or right. You can listen again anytime. If something finds you, I'll tell you what to do, one time, so listen carefully! You've got this. Probably."),
        l("intro_4",
          "You have three hearts. Lose them all and the hallway keeps you. Now then. Let us begin.",
          "You have three hearts. If you lose them all, you stay here forever! With me! Okay, here we go!"),
        l("welcome_back",
          "Ah. You came back. Of course you did. Let's continue.",
          "You're back! I knew you'd come back. Nobody ever really leaves. Let's keep going!"),
        l("new_run",
          "A fresh start. The hallway has been rearranged.",
          "A brand new night! I moved all the doors around for you!"),
    ]

    static let hours: [Line] = (1...24).map { h in
        let n = numbers[h - 1]
        let special: (String, String)
        switch h {
        case 6: special = ("Hour six. A quarter of the way. Not bad.", "Hour six! A quarter done! I'm so proud of you!")
        case 12: special = ("Hour twelve. Halfway. Most guests don't see this hour.", "Hour twelve! Halfway! Most people never get this far. You're special.")
        case 18: special = ("Hour eighteen. The hallway is getting… hungry.", "Hour eighteen! The hallway is getting hungry. Don't worry. It's not hungry for me.")
        case 23: special = ("Hour twenty three. One more after this. I almost don't want you to go.", "Hour twenty three! Just one more after this. Please don't go. Just kidding! Unless?")
        case 24: special = ("Hour twenty four. The last door. Make it count.", "Hour twenty four! The very last door! Oh, I'm going to miss you.")
        default: special = ("Hour \(n).", "Hour \(n)!")
        }
        return l("hour_\(h)", special.0, special.1)
    }

    static let doors: [Line] = [
        l("doors_1", "Two doors. Listen.", "Two doors! Listen closely."),
        l("doors_2", "Left, or right. Listen carefully.", "Left or right? Listen!"),
        l("doors_3", "Here are your doors.", "Ooh, I love these doors. Listen."),
        l("doors_4", "Pay attention to what's behind them.", "Shh. Listen to what's behind them."),
        l("doors_5", "Two more doors. They never end, you know.", "More doors! There are always more doors."),
        l("doors_6", "Listen. And choose wisely.", "Listen, then pick wisely! Or don't. It's more fun for me."),
        l("doors_help",
          "Choose the left door or the right door. Or listen again.",
          "Pick the left door or the right door. Or listen again!"),
        l("open_1", "In you go.", "In you go!"),
        l("open_2", "Bold choice.", "Ooh, brave!"),
        l("open_3", "Let's see.", "Let's see, let's see!"),
        l("open_4", "Hmm. Interesting.", "Oh, interesting!"),
    ]

    static let rooms: [Line] = [
        l("room_bedroom_1", "A bedroom. Have a rest. One heart back.", "A cozy bedroom! Take a nap. You get a heart back!"),
        l("room_bedroom_2", "A soft bed. Lie down for a moment. You feel better.", "A soft little bed! Rest a bit. All better!"),
        l("room_bedroom_full", "A bedroom, but you're already rested. A shame to waste it.", "A bedroom! But you're already feeling great. Aww."),
        l("room_kitchen_1", "A kitchen. There's a bandage in the drawer. Take it.", "A kitchen! There's a bandage in the drawer. It's yours!"),
        l("room_kitchen_2", "The kitchen. Something's cooking. Never mind what. There's a bandage by the sink.", "The kitchen! Something smells, um, interesting. Here, a bandage!"),
        l("room_vault_1", "The vault. Tokens. Spend them in my shop.", "The vault! Shiny tokens! Spend them in my shop!"),
        l("room_vault_2", "Tokens on the floor. Nobody will miss them. Probably.", "Tokens everywhere! Grab them! I won't tell."),
        l("room_storage_1", "A storage closet. You find something useful.", "A storage closet! Ooh, you found something!"),
        l("room_storage_2", "Boxes. Old boxes. And in one of them, something for you.", "Lots of old boxes. And one of them has a present for you!"),
        l("room_empty_1", "An empty room. Nothing happens. Enjoy it.", "An empty room! Nothing happens. Isn't that nice?"),
        l("room_empty_2", "Nothing here. Just a chair. Facing the wall. Don't ask.", "Nothing in here! Just a chair facing the wall. Don't worry about the chair."),
        l("room_empty_3", "Empty. Quiet. Suspiciously quiet.", "So quiet! Too quiet? No, it's fine!"),
        l("found_lighter", "A lighter.", "A lighter!"),
        l("found_bandage", "A bandage.", "A bandage!"),
        l("found_charm", "A lucky charm. Lucky you.", "A lucky charm! Lucky, lucky you!"),
        l("tokens_2", "Two tokens.", "Two tokens!"),
        l("tokens_3", "Three tokens.", "Three tokens!"),
        l("tokens_1", "One token. Don't spend it all at once.", "One token! Every token counts!"),
    ]

    static let lighter: [Line] = [
        l("lighter_left", "You light the lighter and peek under the left door. Behind it:", "You flick the lighter and peek under the left door. There's"),
        l("lighter_right", "And under the right door:", "And under the right door, there's"),
        l("lighter_none", "You don't have a lighter. My shop sells them.", "No lighter! You can buy one in my shop!"),
        l("see_bedroom", "a bed.", "a bed!"),
        l("see_kitchen", "a kitchen.", "a kitchen!"),
        l("see_vault", "something shiny.", "something shiny!"),
        l("see_storage", "boxes.", "some boxes!"),
        l("see_empty", "nothing at all.", "nothing at all!"),
        l("see_drip", "a puddle. Growing.", "a big puddle. It's growing!"),
        l("see_static", "sparks.", "sparks! Zappy!"),
        l("see_crawler", "scratch marks.", "scratch marks. Lots of them."),
        l("see_counter", "someone sitting very still.", "someone sitting very, very still."),
        l("see_mimic", "something pretending to be a room.", "something pretending to be a room. Sneaky!"),
    ]

    static let creatures: [Line] = [
        l("learn_drip",
          "Oh dear. The Drip. When the dripping speeds up and you hear the splash, swipe down to hide in the locker. Not before the splash.",
          "Uh oh, it's the Drip! Wait for the big splash, then swipe down to hide in the locker. Not too early!"),
        l("learn_static",
          "Static. A buzz will come from one side. Swipe the other way. Away from it. Several times.",
          "It's Static! When you hear a buzz on one side, swipe the other way! Away from it! It keeps coming back!"),
        l("learn_crawler",
          "The Crawler. Listen to the steps. If it growls, swipe up and run. If it sniffs, don't move at all. Don't run early.",
          "The Crawler! If it growls, swipe up and run! If it sniffs, freeze! Don't run too early!"),
        l("learn_counter",
          "The Counter. It counts to zero. Don't touch anything until it sighs and leaves. Nothing at all.",
          "It's the Counter! It counts down. Don't touch anything until it sighs and goes away. Nothing! Not even a little tap!"),
        l("learn_mimic",
          "The Mimic. You'll hear two voices, left and right. The lower one is the Mimic. Swipe toward the real one. Tap to hear them again.",
          "The Mimic! Two voices, left and right. The lower one is the Mimic. Swipe toward the real one! Tap to hear them again."),
        l("meet_drip", "The Drip. Wait for the splash.", "The Drip! Wait for the splash!"),
        l("meet_static", "Static. Swipe away from the buzz.", "Static! Swipe away from the buzz!"),
        l("meet_crawler", "The Crawler. Growl means run. Sniff means freeze.", "The Crawler! Growl, run. Sniff, freeze!"),
        l("meet_counter", "The Counter. Don't move.", "The Counter! Freeze!"),
        l("meet_mimic", "The Mimic. Find the real voice.", "The Mimic! Find the real voice!"),
        l("caught_drip_early", "Too early. It heard the locker door.", "Oops, too early! It heard the locker."),
        l("caught_drip_late", "Too late. It found you.", "Too slow! It found you."),
        l("caught_static", "The static got you. Away from the buzz, remember.", "Zap! Away from the buzz, remember?"),
        l("caught_crawler_early", "You ran too soon. It chased you.", "You ran too early! It chased you!"),
        l("caught_crawler_late", "It growled. You should have run.", "It growled! That means run!"),
        l("caught_crawler_moved", "You moved. It heard you.", "You moved! It heard you!"),
        l("caught_counter", "You moved. The Counter doesn't like that.", "You moved! The Counter hates that."),
        l("caught_mimic", "Wrong voice. That was the Mimic.", "Wrong one! That was the Mimic!"),
    ]

    static let results: [Line] = [
        l("survived_1", "You survived. Well done.", "You did it! I'm so proud!"),
        l("survived_2", "Still alive. Impressive.", "Still alive! Yay!"),
        l("survived_3", "It's gone. For now.", "It's gone! Bye bye!"),
        l("survived_4", "Nicely done. Truly.", "Amazing! You're amazing!"),
        l("survived_5", "Hm. You're better at this than the last one.", "You're so much better than the last guest!"),
        l("hurt_2", "Two hearts left.", "Two hearts left! It's okay!"),
        l("hurt_1", "One heart left. Do be careful.", "Only one heart left! Be careful, okay?"),
        l("charm_saved", "Your lucky charm breaks instead of you. Lucky.", "Your lucky charm broke instead of you! Lucky!"),
        l("lose_1", "And that's the end of you. Don't worry. The hallway will keep you safe. Forever.", "Oh no! You're out of hearts. That means you stay here with me. Forever! Yay!"),
        l("lose_2", "Out of hearts. A pity. You were doing so well. Well, you were doing.", "No more hearts! Aww. Don't worry, I'll find a nice room for you."),
        l("win_1", "Twenty four hours. You actually did it. The sun is coming up. You may leave. This time.", "You did it! Twenty four hours! The sun is up! You can go home! Come back soon, okay? Okay?"),
        l("win_2", "Dawn. You survived the night. I'm almost proud. Almost.", "It's morning! You survived the whole night! I'm so proud I could cry!"),
    ]

    static let shop: [Line] = [
        l("shop_welcome_1", "Welcome to my little shop. Spend your tokens. Then back to the hallway.", "Welcome to my shop! Spend your tokens on something nice!"),
        l("shop_welcome_2", "The shop is open. Prices are fair. Mostly.", "Shop time! Everything's on sale! Not really, but it feels nice to say."),
        l("shop_buy_1", "Excellent choice.", "Great choice!"),
        l("shop_buy_2", "A wise purchase.", "Ooh, good pick!"),
        l("shop_poor", "You can't afford that.", "Not enough tokens! Sorry!"),
        l("shop_bye", "Off you go, then. The hallway is waiting.", "Bye for now! The hallway missed you!"),
    ]

    static let items: [Line] = [
        l("bandage_used", "You wrap the bandage. One heart back.", "Bandage on! One heart back!"),
        l("bandage_full", "You're not hurt. Save it.", "You're not hurt! Save it for later!"),
        l("bandage_none", "You don't have a bandage.", "You don't have a bandage!"),
    ]

    static let flavor: [Line] = [
        l("tease_1", "Did you hear that? No? Good.", "Did you hear that? No? Okay, good!"),
        l("tease_2", "The last guest picked left a lot. Just saying.", "The last guest picked left a lot! Just saying!"),
        l("tease_3", "I do enjoy our time together.", "I love spending time with you!"),
        l("tease_4", "Don't mind the scratching. It's the walls. They do that.", "Ignore the scratching! The walls do that sometimes."),
        l("tease_5", "You're very brave. Or very lost.", "You're so brave! Or so lost! Either way!"),
        l("tease_6", "I've rearranged a few doors. For fun.", "I moved some doors around. For fun!"),
        l("late_1", "You know, nobody's made it this far in a while.", "Nobody's made it this far in ages. I'm getting nervous. For you!"),
        l("late_2", "The doors are getting louder. Have you noticed?", "The doors are getting louder! Did you notice?"),
        l("late_3", "Must you really leave in the morning?", "You don't really want to leave in the morning, do you?"),
    ]
}
