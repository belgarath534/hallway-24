import Foundation

/// A hidden mode for making App Store screenshots in the simulator:
///   Hallway24 -screenshot menu|creature|hosts|practice|howto  [-language en|pt]
/// It opens straight to that screen, with the language and Host already chosen, and never touches the real save.
enum ScreenshotMode {
    static let screen: String? = argument("-screenshot")
    static let language: String? = argument("-language")

    static var isOn: Bool { screen != nil }

    private static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
