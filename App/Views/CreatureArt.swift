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
