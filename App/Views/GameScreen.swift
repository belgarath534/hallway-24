import HallwayCore
import SwiftUI

struct GameScreen: View {
    @StateObject private var controller: GameController
    @EnvironmentObject var settings: GameSettings
    let close: () -> Void

    init(settings: GameSettings, resume: RunState?, practice: (creature: Creature, difficulty: Double)? = nil, close: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: GameController(settings: settings, resume: resume, practice: practice))
        self.close = close
    }

    var body: some View {
        ZStack {
            HallwayBackground()
            if let won = controller.ended {
                ResultsView(won: won, run: controller.run, close: leave)
            } else {
                switch controller.phase {
                case .hallway: HallwayView(controller: controller)
                case .encounter: EncounterView(controller: controller)
                case .shop: ShopView(controller: controller)
                case .practiceOver: PracticeOverView(controller: controller, close: leave)
                case .busy, .won, .lost: BusyView(controller: controller)
                }
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .sheet(isPresented: Binding(get: { controller.paused }, set: { if !$0 { controller.setPaused(false) } })) {
            PauseView(controller: controller, quit: leave)
                .environmentObject(settings)
        }
        .statusBarHidden()
    }

    private func leave() {
        controller.quit()
        close()
    }
}

/// Hearts, hour and tokens.
struct StatusBar: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject var controller: GameController

    var body: some View {
        let run = controller.run, t = settings.t
        if controller.game.practice != nil {
            Text(t("Practice Room", "Sala de Treino")).font(.headline).padding(.horizontal)
        } else {
            HStack {
                Text(t("Hour \(run.hour)", "Hora \(run.hour)")).font(.headline.monospacedDigit())
                Text(t("· door \(run.step) of \(Game.roomsPerHour)", "· porta \(run.step) de \(Game.roomsPerHour)"))
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<Game.maxHealth, id: \.self) { i in
                        Image(systemName: i < run.health ? "heart.fill" : "heart")
                            .foregroundStyle(.red)
                    }
                }
                Text("\(run.tokens)").font(.headline.monospacedDigit())
                Image(systemName: "circle.circle.fill").foregroundStyle(.yellow)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(t("Hour \(run.hour), door \(run.step) of \(Game.roomsPerHour). \(run.health) \(run.health == 1 ? "heart" : "hearts"). \(run.tokens) tokens.",
                                  "Hora \(run.hour), porta \(run.step) de \(Game.roomsPerHour). \(run.health) \(run.health == 1 ? "coração" : "corações"). \(run.tokens) fichas.")
                                + (run.coinDoors > 0 ? t(" Double tokens for \(run.coinDoors) doors.", " Fichas em dobro por \(run.coinDoors) portas.") : ""))
        }
    }
}

/// What the Host is saying, and the latest sound caption.
struct CaptionBox: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject var controller: GameController

    var body: some View {
        if settings.captions {
            VStack(spacing: 8) {
                if controller.talking {
                    Text(controller.hostText)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                }
                if !controller.caption.isEmpty {
                    Text(controller.caption).font(.callout.italic()).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            // VoiceOver users hear the Host directly; reading captions too would talk over the game.
            .accessibilityHidden(true)
        }
    }
}

/// Pause and Skip, at the bottom of most screens.
struct BottomButtons: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject var controller: GameController

    var body: some View {
        HStack {
            Button(settings.t("Pause", "Pausar")) { controller.setPaused(true) }
            Spacer()
            Button(settings.t("Skip", "Pular")) { controller.input(.skip) }
                .disabled(!controller.talking)
        }
        .buttonStyle(.bordered)
        .padding()
    }
}

/// Something is happening. Tap anywhere to skip what the Host is saying.
struct BusyView: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack {
            StatusBar(controller: controller).padding(.top)
            Spacer()
            CaptionBox(controller: controller)
            Spacer()
            BottomButtons(controller: controller)
        }
        .contentShape(Rectangle())
        .onTapGesture { controller.input(.skip) }
    }
}

/// Two doors. Choose, listen again, or use an item.
struct HallwayView: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject var controller: GameController
    @AccessibilityFocusState private var focusLeft: Bool

    var body: some View {
        let t = settings.t, run = controller.run
        VStack(spacing: 14) {
            StatusBar(controller: controller).padding(.top)
            Spacer()
            CaptionBox(controller: controller)
            HStack(spacing: 16) {
                DoorButton(title: t("Left door", "Porta da esquerda"), systemImage: "arrow.left") { controller.input(.left) }
                    .accessibilityFocused($focusLeft)
                DoorButton(title: t("Right door", "Porta da direita"), systemImage: "arrow.right") { controller.input(.right) }
            }
            .padding(.horizontal)
            Button {
                controller.input(.listen)
            } label: {
                Label(t("Listen again", "Escutar de novo"), systemImage: "ear").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(Item.allCases.filter(\.usable), id: \.self) { item in
                    ItemButton(item: item, count: run.count(item)) { controller.input(.use(item)) }
                }
            }
            .padding(.horizontal)
            let passive = Item.allCases.filter { !$0.usable && run.count($0) > 0 }
            if !passive.isEmpty {
                Text(t("Working by themselves: ", "Funcionando sozinhos: ")
                     + passive.map { "\($0.name(settings.language)) (\(run.count($0)))" }.joined(separator: ", "))
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
            }
            BottomButtons(controller: controller)
        }
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            // Sighted players can also swipe left or right anywhere.
            if abs(v.translation.width) > abs(v.translation.height) {
                controller.input(v.translation.width < 0 ? .left : .right)
            }
        })
        .onAppear { focusLeft = true }
    }
}

struct DoorButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "door.left.hand.closed").font(.system(size: 52))
                Label(title, systemImage: systemImage).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.35, green: 0.2, blue: 0.12))
        .accessibilityLabel(title)
    }
}

struct ItemButton: View {
    @EnvironmentObject var settings: GameSettings
    let item: Item
    let count: Int
    let action: () -> Void

    var body: some View {
        let name = item.name(settings.language)
        Button(action: action) {
            Text("\(name) (\(count))").frame(maxWidth: .infinity).lineLimit(2).minimumScaleFactor(0.8)
        }
        .buttonStyle(.bordered)
        .disabled(count == 0)
        .accessibilityLabel(settings.t("Use \(name). You have \(count).", "Usar \(name). Você tem \(count)."))
        .accessibilityHint(item.about(settings.language))
    }
}

/// A creature or the Echo. The whole screen is the play area.
struct EncounterView: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject var controller: GameController

    var body: some View {
        let t = settings.t
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 20) {
                StatusBar(controller: controller).padding(.top)
                Spacer()
                if let c = controller.creature { CreaturePicture(creature: c, height: 220).padding(.horizontal).opacity(0.85) }
                Text(controller.creature?.name(settings.language) ?? "").font(.system(size: 40, weight: .heavy, design: .serif))
                if controller.creature == .echo {
                    Text(t("Mistakes: \(controller.game.encounter?.mistakes ?? 0) of 3", "Erros: \(controller.game.encounter?.mistakes ?? 0) de 3"))
                        .font(.headline)
                }
                CaptionBox(controller: controller)
                Spacer()
                Text(t("Swipe left, right, up or down. Tap. Two fingers to pause.", "Deslize para esquerda, direita, cima ou baixo. Toque. Dois dedos para pausar."))
                    .font(.footnote).foregroundStyle(.secondary).padding(.bottom)
            }
            .accessibilityHidden(true)
            TouchPad(label: t("Play area", "Área de jogo"),
                     hint: t("Touches go straight to the game. Two-finger tap to pause.", "Os toques vão direto para o jogo. Toque com dois dedos para pausar."),
                     onInput: { controller.input($0) },
                     onPause: { controller.setPaused(true) })
                .ignoresSafeArea()
        }
    }
}

/// The Host's shop: after hours 6, 12 and 18.
struct ShopView: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject var controller: GameController

    var body: some View {
        let t = settings.t, run = controller.run, l = settings.language
        VStack {
            StatusBar(controller: controller).padding(.top)
            CaptionBox(controller: controller)
            List {
                Section(t("The Host's Shop. You have \(run.tokens) tokens.", "A Loja do Apresentador. Você tem \(run.tokens) fichas.")) {
                    ForEach(Item.allCases, id: \.self) { item in
                        Button {
                            controller.input(.buy(item))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t("\(item.name(l)): \(item.price) tokens", "\(item.name(l)): \(item.price) fichas")).font(.headline)
                                Text(item.about(l)).font(.footnote).foregroundStyle(.secondary)
                                Text(t("You have \(run.count(item))", "Você tem \(run.count(item))")).font(.footnote)
                            }
                        }
                        .disabled(run.tokens < item.price)
                        .accessibilityLabel(t("Buy \(item.name(l)), \(item.price) tokens. You have \(run.count(item)).",
                                              "Comprar \(item.name(l)), \(item.price) fichas. Você tem \(run.count(item))."))
                        .accessibilityHint(item.about(l))
                    }
                }
                Section {
                    Button(t("Back to the hallway", "Voltar ao corredor")) { controller.input(.leave) }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// Practice Room: the challenge is over.
struct PracticeOverView: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject var controller: GameController
    let close: () -> Void

    var body: some View {
        let t = settings.t
        VStack(spacing: 16) {
            StatusBar(controller: controller).padding(.top)
            Spacer()
            CaptionBox(controller: controller)
            Button {
                controller.input(.again)
            } label: {
                Label(t("Try again", "Tentar de novo"), systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            Button(t("Back to the Practice Room", "Voltar à Sala de Treino"), action: close)
                .buttonStyle(.bordered)
            Spacer()
        }
    }
}

struct PauseView: View {
    @ObservedObject var controller: GameController
    @EnvironmentObject var settings: GameSettings
    let quit: () -> Void

    var body: some View {
        let t = settings.t, run = controller.run, practice = controller.game.practice != nil
        NavigationStack {
            List {
                Section {
                    if !practice {
                        Text(t("Hour \(run.hour). \(run.health) \(run.health == 1 ? "heart" : "hearts"). \(run.tokens) tokens.",
                               "Hora \(run.hour). \(run.health) \(run.health == 1 ? "coração" : "corações"). \(run.tokens) fichas."))
                    }
                    Button(t("Keep playing", "Continuar jogando")) { controller.setPaused(false) }
                }
                Section {
                    Button(practice ? t("Leave the Practice Room", "Sair da Sala de Treino") : t("Leave for now", "Sair por enquanto"),
                           role: .destructive, action: quit)
                } footer: {
                    if !practice {
                        Text(t("Your night is saved. Next time you continue from the start of this door.",
                               "Sua noite está salva. Da próxima vez você continua do começo desta porta."))
                    }
                }
            }
            .navigationTitle(t("Paused", "Pausado"))
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

struct ResultsView: View {
    @EnvironmentObject var settings: GameSettings
    let won: Bool
    let run: RunState
    let close: () -> Void

    var body: some View {
        let t = settings.t
        List {
            Section {
                Text(won ? t("You survived the night.", "Você sobreviveu à noite.") : t("The hallway kept you.", "O corredor ficou com você."))
                    .font(.largeTitle.bold())
                Text(won ? t("All twenty four hours.", "Todas as vinte e quatro horas.") : t("You reached hour \(run.hour).", "Você chegou à hora \(run.hour)."))
            }
            Section(t("Your night", "Sua noite")) {
                Text(t("Creatures and puzzles survived: \(run.stats.survived)", "Criaturas e enigmas vencidos: \(run.stats.survived)"))
                Text(t("Times you got caught: \(run.stats.hits)", "Vezes que te pegaram: \(run.stats.hits)"))
                Text(t("Good rooms found: \(run.stats.safeRooms)", "Quartos bons encontrados: \(run.stats.safeRooms)"))
                Text(t("Tokens found: \(run.stats.tokensEarned)", "Fichas encontradas: \(run.stats.tokensEarned)"))
            }
            Section {
                Button(t("Back to the menu", "Voltar ao menu"), action: close)
            }
        }
        .scrollContentBackground(.hidden)
    }
}
