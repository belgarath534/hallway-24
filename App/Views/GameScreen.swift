import HallwayCore
import SwiftUI

struct GameScreen: View {
    @StateObject private var controller: GameController
    @EnvironmentObject var settings: GameSettings
    let close: () -> Void

    init(settings: GameSettings, resume: RunState?, close: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: GameController(settings: settings, resume: resume))
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
    let run: RunState

    var body: some View {
        HStack {
            Text("Hour \(run.hour)").font(.headline.monospacedDigit())
            Text("· door \(run.step) of \(Game.roomsPerHour)").font(.subheadline).foregroundStyle(.secondary)
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
        .accessibilityLabel("Hour \(run.hour), door \(run.step) of \(Game.roomsPerHour). \(run.health) \(run.health == 1 ? "heart" : "hearts"). \(run.tokens) tokens.")
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

/// Something is happening. Tap anywhere to skip what the Host is saying.
struct BusyView: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack {
            StatusBar(run: controller.run).padding(.top)
            Spacer()
            CaptionBox(controller: controller)
            Spacer()
            HStack {
                Button("Pause") { controller.setPaused(true) }
                Spacer()
                Button("Skip") { controller.input(.skip) }
                    .disabled(!controller.talking)
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture { controller.input(.skip) }
    }
}

/// Two doors. Choose, listen again, or use an item.
struct HallwayView: View {
    @ObservedObject var controller: GameController
    @AccessibilityFocusState private var focusLeft: Bool

    var body: some View {
        VStack(spacing: 16) {
            StatusBar(run: controller.run).padding(.top)
            Spacer()
            CaptionBox(controller: controller)
            HStack(spacing: 16) {
                DoorButton(title: "Left door", systemImage: "arrow.left") { controller.input(.left) }
                    .accessibilityFocused($focusLeft)
                DoorButton(title: "Right door", systemImage: "arrow.right") { controller.input(.right) }
            }
            .padding(.horizontal)
            Button {
                controller.input(.listen)
            } label: {
                Label("Listen again", systemImage: "ear").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal)
            HStack {
                ItemButton(item: .lighter, count: controller.run.count(.lighter)) { controller.input(.use(.lighter)) }
                ItemButton(item: .bandage, count: controller.run.count(.bandage)) { controller.input(.use(.bandage)) }
            }
            .padding(.horizontal)
            if controller.run.count(.charm) > 0 {
                Text("Lucky charm: \(controller.run.count(.charm))").font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button("Pause") { controller.setPaused(true) }
                Spacer()
                Button("Skip") { controller.input(.skip) }.disabled(!controller.talking)
            }
            .buttonStyle(.bordered)
            .padding()
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
                Image(systemName: "door.left.hand.closed").font(.system(size: 56))
                Label(title, systemImage: systemImage).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 170)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.35, green: 0.2, blue: 0.12))
        .accessibilityLabel(title)
    }
}

struct ItemButton: View {
    let item: Item
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(item.name) (\(count))").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(count == 0)
        .accessibilityLabel("Use \(item.name). You have \(count).")
        .accessibilityHint(item.about)
    }
}

/// A creature. The whole screen is the play area.
struct EncounterView: View {
    @ObservedObject var controller: GameController

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 20) {
                StatusBar(run: controller.run).padding(.top)
                Spacer()
                Text(controller.creature?.name ?? "").font(.system(size: 40, weight: .heavy, design: .serif))
                CaptionBox(controller: controller)
                Spacer()
                Text("Swipe left, right, up or down. Tap. Two fingers to pause.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.bottom)
            }
            .accessibilityHidden(true)
            TouchPad(label: "Play area",
                     hint: "Touches go straight to the game. Two-finger tap to pause.",
                     onInput: { controller.input($0) },
                     onPause: { controller.setPaused(true) })
                .ignoresSafeArea()
        }
    }
}

/// The Host's shop: every sixth hour.
struct ShopView: View {
    @ObservedObject var controller: GameController

    var body: some View {
        VStack {
            StatusBar(run: controller.run).padding(.top)
            CaptionBox(controller: controller)
            List {
                Section("The Host's Shop. You have \(controller.run.tokens) tokens.") {
                    ForEach(Item.allCases, id: \.self) { item in
                        Button {
                            controller.input(.buy(item))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(item.name): \(item.price) tokens").font(.headline)
                                Text(item.about).font(.footnote).foregroundStyle(.secondary)
                                Text("You have \(controller.run.count(item))").font(.footnote)
                            }
                        }
                        .disabled(controller.run.tokens < item.price)
                        .accessibilityLabel("Buy \(item.name), \(item.price) tokens. You have \(controller.run.count(item)).")
                        .accessibilityHint(item.about)
                    }
                }
                Section {
                    Button("Back to the hallway") { controller.input(.leave) }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

struct PauseView: View {
    @ObservedObject var controller: GameController
    @EnvironmentObject var settings: GameSettings
    let quit: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Hour \(controller.run.hour). \(controller.run.health) \(controller.run.health == 1 ? "heart" : "hearts"). \(controller.run.tokens) tokens.")
                    Button("Keep playing") { controller.setPaused(false) }
                }
                Section {
                    Button("Leave for now", role: .destructive, action: quit)
                } footer: {
                    Text("Your night is saved. Next time you continue from the start of this door.")
                }
            }
            .navigationTitle("Paused")
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

struct ResultsView: View {
    let won: Bool
    let run: RunState
    let close: () -> Void

    var body: some View {
        List {
            Section {
                Text(won ? "You survived the night." : "The hallway kept you.")
                    .font(.largeTitle.bold())
                Text(won ? "All twenty four hours." : "You reached hour \(run.hour).")
            }
            Section("Your night") {
                Text("Creatures survived: \(run.stats.survived)")
                Text("Times you got caught: \(run.stats.hits)")
                Text("Good rooms found: \(run.stats.safeRooms)")
                Text("Tokens found: \(run.stats.tokensEarned)")
            }
            Section {
                Button("Back to the menu", action: close)
            }
        }
        .scrollContentBackground(.hidden)
    }
}
