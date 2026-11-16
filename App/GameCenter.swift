import GameKit
import HallwayCore
import UIKit

/// Game Center: signs the player in, reports achievements and leaderboard scores, and shows the dashboard.
/// Achievements are also kept on the phone (GameSettings), so nothing is lost when Game Center isn't
/// available; everything already earned is sent again each time the player signs in.
@MainActor
final class GameCenter: NSObject, ObservableObject, GKGameCenterControllerDelegate {
    static let shared = GameCenter()

    @Published private(set) var isAuthenticated = false
    /// Called after signing in, to send what was earned before.
    var onAuthenticated: (() -> Void)?

    func authenticate() {
        guard !ScreenshotMode.isOn else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let viewController {
                    // Apple's sign-in screen; it only appears if the player isn't signed in on this device.
                    Self.topViewController()?.present(viewController, animated: true)
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                // The floating Game Center button would sit on top of the play area: keep it hidden.
                GKAccessPoint.shared.isActive = false
                if self.isAuthenticated { self.onAuthenticated?() }
            }
        }
    }

    func report(_ ids: [String]) {
        guard isAuthenticated, !ids.isEmpty else { return }
        let items = ids.compactMap(Achievement.named).map { a -> GKAchievement in
            let item = GKAchievement(identifier: a.gameCenterID)
            item.percentComplete = 100
            item.showsCompletionBanner = true
            return item
        }
        GKAchievement.report(items) { _ in }
    }

    func submit(_ scores: [Leaderboard: Int]) {
        guard isAuthenticated else { return }
        for (board, score) in scores where score > 0 {
            GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [board.rawValue]) { _ in }
        }
    }

    func showDashboard() {
        guard isAuthenticated else { return }
        let vc = GKGameCenterViewController(state: .dashboard)
        vc.gameCenterDelegate = self
        Self.topViewController()?.present(vc, animated: true)
    }

    nonisolated func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
        Task { @MainActor in controller.dismiss(animated: true) }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
