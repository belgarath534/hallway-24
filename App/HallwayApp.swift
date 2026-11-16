import HallwayCore
import SwiftUI

@main
struct HallwayApp: App {
    @StateObject private var settings = GameSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.95, green: 0.78, blue: 0.45))
        }
    }
}

/// First launch: choose your language, then your Host. After that: the menu.
struct RootView: View {
    @EnvironmentObject var settings: GameSettings

    var body: some View {
        if !settings.languageChosen {
            LanguagePickerView(firstTime: true)
        } else if settings.hostChosen {
            MenuView()
        } else {
            NavigationStack {
                HostPickerView(firstTime: true)
            }
        }
    }
}

/// English or Portuguese: menus, Hosts and creature voices.
struct LanguagePickerView: View {
    @EnvironmentObject var settings: GameSettings
    @Environment(\.dismiss) private var dismiss
    let firstTime: Bool

    var body: some View {
        List {
            Section {
                Text("Choose your language.\nEscolha seu idioma.")
                    .font(.title3)
            }
            ForEach(Language.allCases, id: \.self) { lang in
                Button {
                    settings.language = lang
                    if firstTime {
                        settings.hostChosen = false
                        settings.languageChosen = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Label(lang.name, systemImage: settings.language == lang && settings.languageChosen ? "checkmark.circle.fill" : "globe")
                        .font(.title3)
                }
                .accessibilityAddTraits(settings.language == lang && settings.languageChosen ? .isSelected : [])
            }
        }
        .navigationTitle(firstTime ? "Hallway 24" : settings.t("Language", "Idioma"))
        .scrollContentBackground(.hidden)
        .background(HallwayBackground())
    }
}
