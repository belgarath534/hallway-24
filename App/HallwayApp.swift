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

/// First launch: choose your Host. After that: the menu.
struct RootView: View {
    @EnvironmentObject var settings: GameSettings

    var body: some View {
        if settings.hostChosen {
            MenuView()
        } else {
            NavigationStack {
                HostPickerView(firstTime: true)
            }
        }
    }
}
