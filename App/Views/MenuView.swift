import HallwayCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var settings: GameSettings
    @State private var playing: PlayRequest?

    struct PlayRequest: Identifiable {
        let id = UUID()
        let resume: RunState?
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hallway 24").font(.system(size: 40, weight: .black, design: .serif))
                        Text("Two doors. Twenty four hours. Listen carefully.")
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
                            Label("Continue: hour \(saved.hour), \(saved.health) \(saved.health == 1 ? "heart" : "hearts")", systemImage: "play.fill")
                        }
                    }
                    Button {
                        settings.clearSavedRun()
                        playing = PlayRequest(resume: nil)
                    } label: {
                        Label(settings.savedRun == nil ? "Start the Night" : "New Night", systemImage: "door.left.hand.open")
                    }
                }

                Section {
                    NavigationLink {
                        HostPickerView(firstTime: false)
                    } label: {
                        Label("Your Host: \(settings.host.name)", systemImage: "person.wave.2")
                    }
                    NavigationLink { HowToPlayView() } label: { Label("How to Play", systemImage: "questionmark.circle") }
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                    NavigationLink { CreditsView() } label: { Label("Credits", systemImage: "music.note") }
                }

                if settings.nightsPlayed > 0 {
                    Section("Your Record") {
                        Text("Nights survived: \(settings.nightsSurvived) of \(settings.nightsPlayed)")
                        Text("Furthest: hour \(settings.bestHour)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HallwayBackground())
        }
        .onAppear { SoundBoard.shared.music(.menu) }
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
