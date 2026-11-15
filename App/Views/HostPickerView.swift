import AVFoundation
import HallwayCore
import SwiftUI

/// Choose who runs the hallway tonight. You can listen to each Host first.
struct HostPickerView: View {
    @EnvironmentObject var settings: GameSettings
    @Environment(\.dismiss) private var dismiss
    let firstTime: Bool
    @State private var preview: AVAudioPlayer?

    var body: some View {
        List {
            Section {
                Text(firstTime
                     ? "Welcome. Before you go in, choose your Host. They'll guide you through the night. Listen to both, then pick one. You can change later in the menu."
                     : "Choose who runs the hallway. Your saved night keeps going with the new Host.")
            }
            ForEach(Host.allCases, id: \.self) { host in
                Section(host.name) {
                    Text(host.about).foregroundStyle(.secondary)
                    Button {
                        listen(host)
                    } label: {
                        Label("Listen to \(host.name)", systemImage: "speaker.wave.2.fill")
                    }
                    Button {
                        preview?.stop()
                        settings.host = host
                        settings.hostChosen = true
                        if !firstTime { dismiss() }
                    } label: {
                        Label(settings.host == host && settings.hostChosen ? "\(host.name) (your Host)" : "Choose \(host.name)",
                              systemImage: settings.host == host && settings.hostChosen ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        }
        .navigationTitle(firstTime ? "Hallway 24" : "Your Host")
        .onDisappear { preview?.stop() }
    }

    private func listen(_ host: Host) {
        preview?.stop()
        guard let url = HostVoice.url("intro_1", host), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.play()
        preview = p
    }
}
