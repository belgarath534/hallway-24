import HallwayCore
import SwiftUI

/// Try any creature or the Echo as many times as you like. Nothing counts and no hearts are lost.
struct PracticeView: View {
    @EnvironmentObject var settings: GameSettings
    @State private var late = false
    @State private var playing: Pick?

    struct Pick: Identifiable {
        let id = UUID()
        let creature: Creature
        let difficulty: Double
    }

    var body: some View {
        let t = settings.t, l = settings.language
        List {
            Section {
                Text(t("Pick a creature or the Echo puzzle. The Host explains it, then you try. Nothing here counts, and you don't lose hearts.",
                       "Escolha uma criatura ou o enigma do Eco. O apresentador explica, e você tenta. Nada aqui conta, e você não perde corações."))
                Picker(t("How hard", "Dificuldade"), selection: $late) {
                    Text(t("Early night (easier)", "Começo da noite (mais fácil)")).tag(false)
                    Text(t("Late night (faster)", "Fim da noite (mais rápido)")).tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(t("How hard", "Dificuldade"))
            }
            Section(t("Creatures", "Criaturas")) {
                ForEach(Creature.allCases, id: \.self) { c in
                    CreaturePicture(creature: c, height: 150)
                    Button {
                        playing = Pick(creature: c, difficulty: late ? 0.85 : 0.1)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.name(l)).font(.headline)
                            Text(c.howTo(l)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(t("Practice \(c.name(l))", "Treinar \(c.name(l))"))
                    .accessibilityHint(c.howTo(l))
                }
            }
        }
        .navigationTitle(t("Practice Room", "Sala de Treino"))
        .scrollContentBackground(.hidden)
        .background(HallwayBackground())
        .fullScreenCover(item: $playing) { pick in
            GameScreen(settings: settings, resume: nil, practice: (pick.creature, pick.difficulty)) {
                playing = nil
                SoundBoard.shared.music(.menu)
            }
            .environmentObject(settings)
        }
    }
}
