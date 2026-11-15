import HallwayCore
import SwiftUI

struct HowToPlayView: View {
    var body: some View {
        List {
            Section("The night") {
                Text("Stay in the hallway for twenty four hours. Every hour has three doors to get through, one after another. Each time, there are two doors: left and right.")
                Text("Use headphones. Every door makes a sound, and the left door's sound plays on your left, the right door's on your right.")
                Text("You have three hearts. Lose them all and the night is over. Your night is saved at every door, so you can stop and continue later.")
            }
            Section("Good rooms") {
                ForEach(SafeRoom.allCases, id: \.self) { room in
                    Text("\(room.name): sounds like \(room.hintDescription). \(effect(room))")
                }
            }
            Section("Creatures") {
                Text("Creatures sound wrong through the door: dripping, buzzing, scratching or ticking. When one finds you, the whole screen becomes the play area. With VoiceOver on, your touches go straight to the game.")
                ForEach(Creature.allCases, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(c.name), from hour \(c.firstHour)").font(.headline)
                        Text(c.howTo)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section("Items") {
                ForEach(Item.allCases, id: \.self) { item in
                    Text("\(item.name): \(item.about) Costs \(item.price) tokens in the Host's shop, which opens after hours 6, 12 and 18.")
                }
            }
            Section("Controls") {
                Text("In the hallway: the Left door and Right door buttons, Listen again, and your items. Sighted players can also swipe left or right anywhere.")
                Text("When the Host is talking: tap Skip, or tap the screen.")
                Text("During a creature: swipe left, right, up or down, or tap. Two-finger tap to pause.")
            }
        }
        .navigationTitle("How to Play")
    }

    private func effect(_ room: SafeRoom) -> String {
        switch room {
        case .bedroom: return "Gives you a heart back."
        case .kitchen: return "Has a bandage."
        case .vault: return "Has tokens."
        case .storage: return "Has a random item."
        case .empty: return "Nothing happens. That's good."
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: GameSettings

    var body: some View {
        Form {
            Section {
                Toggle("Vibration", isOn: $settings.haptics)
                Toggle("Captions on screen", isOn: $settings.captions)
                Toggle("Recorded Host voice", isOn: $settings.recordedHost)
                VStack(alignment: .leading) {
                    Text("Music volume")
                    Slider(value: $settings.musicVolume, in: 0...1)
                        .accessibilityLabel("Music volume")
                        .onChange(of: settings.musicVolume) { _, v in SoundBoard.shared.musicVolume = v }
                }
            } footer: {
                Text("With the recorded voice off, the Host uses your phone's own voice.")
            }
            Section {
                Toggle("Host explains the rules", isOn: $settings.tutorial)
            } footer: {
                Text("At the start of a new night.")
            }
        }
        .navigationTitle("Settings")
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Section("Music") {
                Text("Kevin MacLeod (incompetech.com), licensed under Creative Commons: By Attribution 4.0. \"Comfortable Mystery 4\", \"Lightless Dawn\", \"Penumbra\", \"Ossuary 6 - Air\", \"Clean Soul\", \"Lasting Hope\" and \"Darkness Speaks\".")
            }
            Section("Sounds") {
                Text("\"Abandoned Building Ambience\" by tcarisland (OpenGameArt), CC BY 3.0.")
                Text("\"Horror Sound Effects Library\" by Little Robot Sound Factory (www.littlerobotsoundfactory.com), CC BY 3.0.")
                Text("Sound packs by rubberduck (OpenGameArt): 100 CC0 SFX, 100 CC0 SFX #2, 100 CC0 metal and wood SFX, 80 CC0 creature SFX, 40 CC0 water and slime SFX. CC0.")
                Text("\"Heartbeat sounds\" by bart (OpenGameArt), CC0.")
            }
            Section("Voices") {
                Text("The Hosts, the Counter and the Mimic are voiced with Kokoro (hexgrad), Apache License 2.0.")
            }
        }
        .navigationTitle("Credits")
    }
}
