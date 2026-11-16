import CoreHaptics
import HallwayCore
import UIKit

/// Vibrations you can feel and learn: a heartbeat when a creature is behind a door, a rumble that
/// builds when one lunges at you, a hard thud and a fading shake when you're caught.
/// Made with Core Haptics; phones without it get the simple taps instead.
@MainActor
final class Haptics {
    var enabled = true
    private var engine: CHHapticEngine?
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = try? CHHapticEngine() else { return }
        engine.isAutoShutdownEnabled = true
        engine.playsHapticsOnly = true
        engine.resetHandler = { [weak engine] in try? engine?.start() }
        self.engine = engine
    }

    func play(_ h: Haptic) {
        guard enabled else { return }
        if let engine, let pattern = try? CHHapticPattern(events: Self.events(h), parameterCurves: Self.curves(h)) {
            do {
                try engine.start()
                try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
                return
            } catch {}
        }
        simple(h)
    }

    // MARK: Patterns

    private static func tap(_ time: Double, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)], relativeTime: time)
    }

    private static func rumble(_ time: Double, _ duration: Double, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)], relativeTime: time, duration: duration)
    }

    private static func events(_ h: Haptic) -> [CHHapticEvent] {
        switch h {
        case .light: return [tap(0, 0.55, 0.5)]
        case .heavy: return [tap(0, 1, 0.3)]
        case .warning: return [tap(0, 0.8, 0.8), tap(0.13, 0.8, 0.8)]
        case .success: return [tap(0, 0.5, 0.9), tap(0.1, 0.9, 0.9)]
        // Lub-dub, twice.
        case .heartbeat: return [tap(0, 1, 0.15), tap(0.17, 0.65, 0.15), tap(0.8, 1, 0.15), tap(0.97, 0.65, 0.15)]
        // A rumble that builds, then a hit.
        case .rush: return [rumble(0, 0.55, 1, 0.25), tap(0.55, 1, 0.7)]
        // A hard thud, then a shake that fades.
        case .hit: return [tap(0, 1, 1), rumble(0.04, 0.7, 1, 0.15)]
        }
    }

    private static func curves(_ h: Haptic) -> [CHHapticParameterCurve] {
        func curve(_ points: [(Double, Float)]) -> CHHapticParameterCurve {
            CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                   controlPoints: points.map { .init(relativeTime: $0.0, value: $0.1) }, relativeTime: 0)
        }
        switch h {
        case .rush: return [curve([(0, 0.15), (0.45, 0.8), (0.55, 1)])]
        case .hit: return [curve([(0, 1), (0.2, 0.7), (0.74, 0)])]
        default: return []
        }
    }

    /// Phones without Core Haptics.
    private func simple(_ h: Haptic) {
        switch h {
        case .light: light.impactOccurred()
        case .heavy, .rush, .hit: heavy.impactOccurred(intensity: 1)
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
