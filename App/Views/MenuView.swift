import HallwayCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var settings: GameSettings
    @ObservedObject private var gameCenter = GameCenter.shared
    @State private var playing: PlayRequest?
    @State private var showPractice = false
    @ObservedObject private var launch = AppLaunch.shared

    struct PlayRequest: Identifiable {
        let id = UUID()
        let resume: RunState?
    }

    var body: some View {
        let t = settings.t
        NavigationStack {
            List {
                Section {
                    Image("MenuHallway")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(t("Picture: a long, dark hotel hallway at night. Old wooden doors line both sides, and a single bare bulb hangs from the ceiling. Warm orange light glows from one half-open door on the left. The hallway disappears into darkness at the far end.",
                                              "Imagem: um corredor de hotel longo e escuro, à noite. Portas de madeira antigas dos dois lados, e uma única lâmpada pendurada no teto. Uma luz laranja e quente sai de uma porta entreaberta à esquerda. O corredor some na escuridão lá no fundo."))
                        .accessibilityAddTraits(.isImage)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hallway 24").font(.system(size: 40, weight: .black, design: .serif))
                        Text(t("Two doors. Twenty four hours. Listen carefully.", "Duas portas. Vinte e quatro horas. Escute com atenção."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                .listRowBackground(Color.clear)

                Section {
                    if let saved = settings.savedRun {
                        Button {
                            playing = PlayRequest(resume: saved)
                        } label: {
                            Label(t("Continue: hour \(saved.hour), \(saved.health) \(saved.health == 1 ? "heart" : "hearts")",
                                    "Continuar: hora \(saved.hour), \(saved.health) \(saved.health == 1 ? "coração" : "corações")"),
                                  systemImage: "play.fill")
                        }
                    }
                    Button {
                        settings.clearSavedRun()
                        playing = PlayRequest(resume: nil)
                    } label: {
                        Label(settings.savedRun == nil ? t("Start the Night", "Começar a Noite") : t("New Night", "Nova Noite"),
                              systemImage: "door.left.hand.open")
                    }
                    NavigationLink { PracticeView() } label: {
                        Label(t("Practice Room", "Sala de Treino"), systemImage: "figure.run")
                    }
                }

                Section {
                    NavigationLink {
                        HostPickerView(firstTime: false)
                    } label: {
                        Label(t("Your Host: \(settings.host.name)", "Seu apresentador: \(settings.host.name)"), systemImage: "person.wave.2")
                    }
                    NavigationLink { HowToPlayView() } label: { Label(t("How to Play", "Como Jogar"), systemImage: "questionmark.circle") }
                    NavigationLink { SettingsView() } label: { Label(t("Settings", "Ajustes"), systemImage: "gearshape") }
                    NavigationLink { LanguagePickerView(firstTime: false) } label: {
                        Label(t("Language: English", "Idioma: Português"), systemImage: "globe")
                    }
                    NavigationLink { CreditsView() } label: { Label(t("Credits", "Créditos"), systemImage: "music.note") }
                    if gameCenter.isAuthenticated {
                        Button {
                            gameCenter.showDashboard()
                        } label: {
                            Label(t("Game Center: achievements and leaderboards", "Game Center: conquistas e placares"), systemImage: "trophy")
                        }
                    }
                }

                if settings.nightsPlayed > 0 {
                    Section(t("Your Record", "Seu Recorde")) {
                        Text(t("Nights survived: \(settings.nightsSurvived) of \(settings.nightsPlayed)",
                               "Noites sobrevividas: \(settings.nightsSurvived) de \(settings.nightsPlayed)"))
                        Text(t("Furthest: hour \(settings.bestHour)", "Mais longe: hora \(settings.bestHour)"))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HallwayBackground())
            .navigationDestination(isPresented: $showPractice) { PracticeView() }
        }
        .onAppear { SoundBoard.shared.music(.menu) }
        // Siri, Shortcuts or the Action button opened the game.
        .onReceive(launch.$request) { request in
            guard let request, playing == nil else { return }
            launch.request = nil
            switch request {
            case .night: playing = PlayRequest(resume: settings.savedRun)
            case .practice: showPractice = true
            }
        }
        .fullScreenCover(item: $playing) { request in
            GameScreen(settings: settings, resume: request.resume) { playing = nil }
                .environmentObject(settings)
        }
    }
}

/// A dim hallway with doors fading into the dark.
struct HallwayBackground: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.08, green: 0.05, blue: 0.05), .black], startPoint: .top, endPoint: .bottom)
                ForEach(0..<6) { i in
                    let depth = CGFloat(i) / 6
                    let scale = 1 - depth * 0.8
                    let doorW = w * 0.12 * scale, doorH = h * 0.32 * scale
                    let x = w * 0.5 - w * 0.36 * scale
                    let y = h * 0.62 - h * 0.12 * depth
                    ForEach([x, w - x], id: \.self) { cx in
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color(red: 0.95, green: 0.78, blue: 0.45).opacity(0.25 * (1 - depth)), lineWidth: 1.5)
                            .frame(width: doorW, height: doorH)
                            .position(x: cx, y: y)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
