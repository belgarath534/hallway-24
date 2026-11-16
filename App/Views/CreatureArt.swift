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
        default:
            return ""
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
