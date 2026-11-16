import HallwayCore
import SwiftUI
import UIKit

/// Pictures of the creatures (made with Image Playground), each with a description for VoiceOver.
/// A creature without a picture yet simply shows none.
enum CreatureArt {
    static func imageName(_ c: Creature) -> String { "creature_\(c.rawValue)" }

    static func has(_ c: Creature) -> Bool { UIImage(named: imageName(c)) != nil }

    static func description(_ c: Creature, _ l: Language) -> String {
        switch c {
        case .drip:
            return l.t("Picture: a tall, thin figure made of dripping black liquid stands in a small tiled room under a flickering ceiling light. Black goo runs down its body and spreads into a puddle around its feet. Next to it stands a grey metal locker, the kind you hide in.",
                       "Imagem: uma figura alta e magra, feita de líquido preto escorrendo, está de pé em uma salinha de azulejos sob uma luz fraca no teto. A gosma preta escorre pelo corpo e forma uma poça em volta dos pés. Ao lado, um armário de metal cinza, do tipo em que você se esconde.")
        case .echo:
            return l.t("Picture: an old wooden music box with its lid open, sitting on a velvet cloth on a small table in a dark room. Inside, brass gears and a metal cylinder with tiny pins. A little crank sticks out of its side, and a warm light glows on the wall behind it.",
                       "Imagem: uma caixinha de música antiga de madeira, com a tampa aberta, sobre um pano de veludo em uma mesinha em um quarto escuro. Dentro, engrenagens de latão e um cilindro de metal com pininhos. Uma manivela sai do lado, e uma luz quente brilha na parede atrás.")
        case .staticBuzz:
            return l.t("Picture: a human-shaped creature made of flickering TV static floats above the floor of a run-down hallway with peeling wallpaper. Its body is striped with glitchy colored lines, and crackling blue electricity arcs all around it.",
                       "Imagem: uma criatura em forma de gente, feita de chiado de TV piscando, flutua acima do chão de um corredor velho com o papel de parede descascando. O corpo é cheio de listras coloridas com defeito, e eletricidade azul estala em volta dela toda.")
        case .crawler:
            return l.t("Picture: a pale, skinny creature creeps on four long bony legs down a run-down hallway with peeling wallpaper. You can see its ribs. It has a long thin tail, clawed feet, and it stretches its bald head forward with dark eyes, sniffing the air.",
                       "Imagem: uma criatura pálida e magrela anda em quatro pernas longas e ossudas por um corredor velho de papel de parede descascando. Dá para ver as costelas. Tem um rabo comprido e fino, pés com garras, e estica a cabeça careca para a frente com olhos escuros, farejando o ar.")
        case .counter:
            return l.t("Picture: a very tall, thin, pale man in a dark suit and tie sits perfectly still on a wooden chair in an empty room. His sunken eyes stare down at his long bony fingers as he counts on them.",
                       "Imagem: um homem muito alto, magro e pálido, de terno escuro e gravata, sentado imóvel numa cadeira de madeira em uma sala vazia. Os olhos fundos olham para os dedos longos e ossudos enquanto ele conta neles.")
        case .mimic:
            return l.t("Picture: a dark creature peeks around a half-open wooden door. Its glowing yellow eyes and huge, too-wide grin full of teeth stare out, and one clawed hand grips the edge of the door.",
                       "Imagem: uma criatura escura espia por trás de uma porta de madeira entreaberta. Olhos amarelos brilhando e um sorriso enorme, largo demais, cheio de dentes. Uma mão com garras segura a beirada da porta.")
        default:
            return ""
        }
    }
}

/// Pictures of the Hosts. Lewis em Português shares Lewis's picture.
enum HostArt {
    static func imageName(_ h: Host) -> String { "host_\(h == .lewisPT ? "lewis" : h.rawValue)" }

    static func has(_ h: Host) -> Bool { UIImage(named: imageName(h)) != nil }

    static func description(_ h: Host, _ l: Language) -> String {
        switch h {
        case .lewis, .lewisPT:
            return l.t("Picture: Lewis, a smiling older gentleman with neat silver hair, in a dark tuxedo and black bow tie, holding a lit candle in a brass holder. Behind him, a dark hallway full of doors.",
                       "Imagem: Lewis, um senhor sorridente de cabelo grisalho bem penteado, de smoking escuro e gravata borboleta preta, segurando uma vela acesa num castiçal de latão. Atrás dele, um corredor escuro cheio de portas.")
        case .heart:
            return l.t("Picture: Heart, a young woman with shoulder-length brown hair and a big, warm smile, in a soft pink sweater. She holds up a glowing brass lantern in a dark hallway lined with doors. Her smile is just a little too wide.",
                       "Imagem: Heart, uma moça de cabelo castanho na altura dos ombros e um sorriso enorme e caloroso, de suéter rosa clarinho. Ela segura uma lanterna de latão acesa em um corredor escuro cheio de portas. O sorriso dela é só um pouquinho largo demais.")
        default:
            return ""
        }
    }
}

/// The Host's picture, if they have one.
struct HostPicture: View {
    @EnvironmentObject var settings: GameSettings
    let host: Host
    var height: CGFloat = 220

    var body: some View {
        if HostArt.has(host) {
            Image(HostArt.imageName(host))
                .resizable()
                .scaledToFill()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(HostArt.description(host, settings.language))
                .accessibilityAddTraits(.isImage)
        }
    }
}

/// The creature's picture, if it has one.
struct CreaturePicture: View {
    @EnvironmentObject var settings: GameSettings
    let creature: Creature
    var height: CGFloat = 200

    var body: some View {
        if CreatureArt.has(creature) {
            Image(CreatureArt.imageName(creature))
                .resizable()
                .scaledToFill()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(CreatureArt.description(creature, settings.language))
                .accessibilityAddTraits(.isImage)
        }
    }
}

/// Pictures of places: the shop, the end of a night.
enum SceneArt: String {
    case shop = "scene_shop", lose = "scene_lose", win = "scene_win"

    func description(_ l: Language) -> String {
        switch self {
        case .shop:
            return l.t("Picture: the Host's shop, a dusty wooden counter in a dark corner lit by one candle. On the shelves behind it: a silver lighter, a roll of bandage, a pair of earplugs, an old iron key, a little lucky charm bag and a glowing gold coin.",
                       "Imagem: a loja do apresentador, um balcão de madeira empoeirado num canto escuro, iluminado por uma vela. Nas prateleiras atrás: um isqueiro prateado, um rolo de curativo, protetores de ouvido, uma chave de ferro antiga, um saquinho de amuleto e uma moeda de ouro brilhando.")
        case .lose:
            return l.t("Picture: an empty wooden chair sits alone in the middle of a dark hallway with cracked tiles, under a single dim lamp. Heavy wooden doors line both sides, all shut.",
                       "Imagem: uma cadeira de madeira vazia, sozinha no meio de um corredor escuro de piso rachado, sob uma única lâmpada fraca. Portas pesadas de madeira dos dois lados, todas fechadas.")
        case .win:
            return l.t("Picture: at the end of the dark hallway, a door stands open onto a sunrise. Golden light pours in across the shiny wooden floor and lights up the walls. You made it out.",
                       "Imagem: no fim do corredor escuro, uma porta aberta mostra o nascer do sol. A luz dourada entra pelo chão de madeira brilhante e ilumina as paredes. Você conseguiu sair.")
        }
    }
}

/// A place's picture, if it has one.
struct ScenePicture: View {
    @EnvironmentObject var settings: GameSettings
    let scene: SceneArt
    var height: CGFloat = 200

    var body: some View {
        if UIImage(named: scene.rawValue) != nil {
            Image(scene.rawValue)
                .resizable()
                .scaledToFill()
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(scene.description(settings.language))
                .accessibilityAddTraits(.isImage)
        }
    }
}
