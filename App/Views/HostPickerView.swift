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
        let t = settings.t
        List {
            Section {
                Text(firstTime
                     ? t("Welcome. Before you go in, choose your Host. They'll guide you through the night. Listen to a few, then pick one. You can change later in the menu.",
                         "Boas-vindas. Antes de entrar, escolha seu apresentador. Ele vai te guiar pela noite. Escute alguns e escolha um. Dá para trocar depois no menu.")
                     : t("Choose who runs the hallway. Your saved night keeps going with the new Host.",
                         "Escolha quem comanda o corredor. Sua noite salva continua com o novo apresentador."))
            }
            ForEach(Host.all(settings.language), id: \.self) { host in
                Section(host.name) {
                    HostPicture(host: host)
                    Text(host.about).foregroundStyle(.secondary)
                    Button {
                        listen(host)
                    } label: {
                        Label(t("Listen to \(host.name)", "Ouvir \(host.name)"), systemImage: "speaker.wave.2.fill")
                    }
                    Button {
                        preview?.stop()
                        settings.host = host
                        settings.hostChosen = true
                        if !firstTime { dismiss() }
                    } label: {
                        let chosen = settings.host == host && settings.hostChosen
                        Label(chosen ? t("\(host.name) (your Host)", "\(host.name) (seu apresentador)") : t("Choose \(host.name)", "Escolher \(host.name)"),
                              systemImage: chosen ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        }
        .navigationTitle(firstTime ? "Hallway 24" : t("Your Host", "Seu Apresentador"))
        .onDisappear { preview?.stop() }
    }

    private func listen(_ host: Host) {
        preview?.stop()
        guard let url = HostVoice.url("intro_1", host), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.play()
        preview = p
    }
}
