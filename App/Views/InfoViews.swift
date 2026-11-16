import HallwayCore
import SwiftUI

struct HowToPlayView: View {
    @EnvironmentObject var settings: GameSettings

    var body: some View {
        let t = settings.t, l = settings.language
        List {
            Section(t("The night", "A noite")) {
                Text(t("Stay in the hallway for twenty four hours. Every hour has three pairs of doors to get through, one after another: left or right.",
                       "Fique no corredor por vinte e quatro horas. Cada hora tem três pares de portas, um depois do outro: esquerda ou direita."))
                Text(t("Use headphones. Every door makes a sound, and the left door's sound plays on your left, the right door's on your right.",
                       "Use fones de ouvido. Cada porta faz um som: a da esquerda toca no ouvido esquerdo, a da direita no direito."))
                Text(t("You have three hearts. Lose them all and the night is over. Your night is saved at every door, so you can stop and continue later.",
                       "Você tem três corações. Perca todos e a noite acaba. Sua noite é salva a cada porta, então dá para parar e continuar depois."))
                Text(t("Not sure how a creature works? Try it in the Practice Room first.",
                       "Não entendeu uma criatura? Treine primeiro na Sala de Treino."))
            }
            Section(t("Good rooms", "Quartos bons")) {
                ForEach(SafeRoom.allCases, id: \.self) { room in
                    Text(t("\(room.name(l)): sounds like \(room.hintDescription(l)). \(room.effect(l))",
                           "\(room.name(l)): soa como \(room.hintDescription(l)). \(room.effect(l))"))
                }
            }
            Section(t("Creatures and puzzles", "Criaturas e enigmas")) {
                Text(t("Creatures sound wrong through the door: dripping, buzzing, scratching or ticking. A little music-box tune is the Echo puzzle. When one finds you, the whole screen becomes the play area. With VoiceOver on, your touches go straight to the game.",
                       "As criaturas soam estranhas atrás da porta: gotas, zumbidos, arranhões ou tique-taque. Uma musiquinha de caixinha de música é o enigma do Eco. Quando uma te encontra, a tela inteira vira a área de jogo. Com o VoiceOver ligado, seus toques vão direto para o jogo."))
                ForEach(Creature.allCases, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        CreaturePicture(creature: c, height: 170)
                        Text(t("\(c.name(l)), from hour \(c.firstHour)", "\(c.name(l)), a partir da hora \(c.firstHour)")).font(.headline)
                        Text(c.howTo(l))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section(t("Items", "Itens")) {
                Text(t("Find items in storage closets, or buy them in the Host's shop after hours 6, 12 and 18. Vaults, the Echo and surviving creatures give tokens.",
                       "Ache itens nos depósitos ou compre na loja do apresentador depois das horas 6, 12 e 18. Cofres, o Eco e vencer criaturas dão fichas."))
                ForEach(Item.allCases, id: \.self) { item in
                    Text(t("\(item.name(l)), \(item.price) tokens: \(item.about(l))", "\(item.name(l)), \(item.price) fichas: \(item.about(l))"))
                }
            }
            Section(t("Controls", "Controles")) {
                Text(t("In the hallway: the Left door and Right door buttons, Listen again, and your items. Sighted players can also swipe left or right anywhere.",
                       "No corredor: os botões Porta da esquerda e Porta da direita, Escutar de novo e seus itens. Quem enxerga também pode deslizar para esquerda ou direita em qualquer lugar."))
                Text(t("When the Host is talking: tap Skip, or tap the screen.", "Quando o apresentador estiver falando: toque em Pular, ou toque na tela."))
                Text(t("During a creature or the Echo: swipe left, right, up or down, or tap. Two-finger tap to pause.",
                       "Durante uma criatura ou o Eco: deslize para esquerda, direita, cima ou baixo, ou toque. Toque com dois dedos para pausar."))
            }
        }
        .navigationTitle(t("How to Play", "Como Jogar"))
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: GameSettings

    var body: some View {
        let t = settings.t
        Form {
            Section {
                VolumeSlider(title: t("Music", "Música"), value: $settings.musicVolume)
                VolumeSlider(title: t("Background sounds", "Sons de fundo"), value: $settings.ambienceVolume)
                VolumeSlider(title: t("Effects and creatures", "Efeitos e criaturas"), value: $settings.effectsVolume)
            } header: {
                Text(t("Volume", "Volume"))
            } footer: {
                Text(t("The Host's voice always stays at full volume. Turn the others down if something is hard to hear.",
                       "A voz do apresentador fica sempre no volume máximo. Abaixe os outros se algo estiver difícil de ouvir."))
            }
            Section {
                Toggle(t("Vibration", "Vibração"), isOn: $settings.haptics)
                Toggle(t("Captions on screen", "Legendas na tela"), isOn: $settings.captions)
                Toggle(t("Recorded Host voice", "Voz gravada do apresentador"), isOn: $settings.recordedHost)
            } footer: {
                Text(t("With the recorded voice off, the Host uses your phone's own voice.",
                       "Com a voz gravada desligada, o apresentador usa a voz do próprio celular."))
            }
            Section {
                Toggle(t("Host explains the rules", "Apresentador explica as regras"), isOn: $settings.tutorial)
                Button(t("Practice every creature again", "Treinar todas as criaturas de novo")) { settings.resetPractice() }
                    .disabled(settings.learnedCreatures.isEmpty)
            } footer: {
                Text(t("The rules are explained at the start of a new night. The first time you meet each creature, you get three practice rounds; this brings them back.",
                       "As regras são explicadas no começo de uma noite nova. Na primeira vez que você encontra cada criatura, ganha três rodadas de treino; isto as traz de volta."))
            }
        }
        .navigationTitle(t("Settings", "Ajustes"))
    }
}

struct VolumeSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(title): \(Int((value * 100).rounded()))%")
            Slider(value: $value, in: 0...1, step: 0.05)
                .accessibilityLabel(title)
        }
    }
}

struct CreditsView: View {
    @EnvironmentObject var settings: GameSettings

    var body: some View {
        let t = settings.t
        List {
            Section(t("Music", "Música")) {
                Text(t("Kevin MacLeod (incompetech.com), licensed under Creative Commons: By Attribution 4.0.",
                       "Kevin MacLeod (incompetech.com), licença Creative Commons: Atribuição 4.0.")
                     + " \"Comfortable Mystery 4\", \"Lightless Dawn\", \"Penumbra\", \"Ossuary 6 - Air\", \"Clean Soul\", \"Lasting Hope\", \"Darkness Speaks\".")
            }
            Section(t("Sounds", "Sons")) {
                Text("\"Abandoned Building Ambience\" by tcarisland (OpenGameArt), CC BY 3.0.")
                Text("\"Horror Sound Effects Library\" by Little Robot Sound Factory (www.littlerobotsoundfactory.com), CC BY 3.0.")
                Text("Sound packs by rubberduck (OpenGameArt): 100 CC0 SFX, 100 CC0 SFX #2, 100 CC0 metal and wood SFX, 80 CC0 creature SFX, 40 CC0 water and slime SFX. CC0.")
                Text("\"Heartbeat sounds\" by bart (OpenGameArt), CC0.")
                Text(t("The Echo's music box and Static's zap are made for this game.", "A caixinha de música do Eco e o zap da Estática foram feitos para este jogo."))
            }
            Section(t("Voices", "Vozes")) {
                Text(t("The Hosts, the Counter and the Mimic are voiced with Kokoro (hexgrad), Apache License 2.0.",
                       "Os apresentadores, o Contador e o Imitador têm voz feita com Kokoro (hexgrad), Licença Apache 2.0."))
            }
        }
        .navigationTitle(t("Credits", "Créditos"))
    }
}
