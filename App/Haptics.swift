import HallwayCore
import UIKit

@MainActor
final class Haptics {
    var enabled = true
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    func play(_ h: Haptic) {
        guard enabled else { return }
        switch h {
        case .light: light.impactOccurred()
        case .heavy: heavy.impactOccurred(intensity: 1)
        case .warning: notify.notificationOccurred(.warning)
        case .success: notify.notificationOccurred(.success)
        case .heartbeat:
            heavy.impactOccurred(intensity: 0.9)
            Task { @MainActor [heavy] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                heavy.impactOccurred(intensity: 0.6)
            }
        }
    }
}
