import HallwayCore
import SwiftUI
import UIKit

/// The full-screen play area for creatures: swipes and taps go straight to the game.
///
/// Accessibility: one element with "allows direct interaction", so with VoiceOver on, touches go straight
/// to the game with no double tap. A two-finger tap, VoiceOver's magic tap or the escape scrub pauses.
final class TouchPadView: UIView {
    var onInput: ((Input) -> Void)?
    var onPause: (() -> Void)?

    private struct Track { var start: CGPoint; var time: TimeInterval; var done: Bool }
    private var tracks: [ObjectIdentifier: Track] = [:]
    private static let swipeDistance: CGFloat = 30

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .allowsDirectInteraction
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            UIAccessibility.post(notification: .screenChanged, argument: self)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { tracks[ObjectIdentifier(t)] = Track(start: t.location(in: self), time: t.timestamp, done: false) }
        if (event?.allTouches?.count ?? touches.count) >= 2 {
            for k in tracks.keys { tracks[k]?.done = true }
            onPause?()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            guard let track = tracks[id], !track.done else { continue }
            let p = t.location(in: self)
            let dx = p.x - track.start.x, dy = p.y - track.start.y
            guard hypot(dx, dy) >= Self.swipeDistance else { continue }
            tracks[id]?.done = true
            onInput?(abs(dx) > abs(dy) ? (dx < 0 ? .left : .right) : (dy < 0 ? .up : .down))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let id = ObjectIdentifier(t)
            if let track = tracks[id], !track.done, t.timestamp - track.time < 0.5 { onInput?(.tap) }
            tracks[id] = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { tracks[ObjectIdentifier(t)] = nil }
    }

    override func accessibilityPerformMagicTap() -> Bool { onPause?(); return true }
    override func accessibilityPerformEscape() -> Bool { onPause?(); return true }
}

struct TouchPad: UIViewRepresentable {
    var label: String
    var hint: String
    var onInput: (Input) -> Void
    var onPause: () -> Void

    func makeUIView(context: Context) -> TouchPadView { TouchPadView() }

    func updateUIView(_ view: TouchPadView, context: Context) {
        view.accessibilityLabel = label
        view.accessibilityHint = hint
        view.onInput = onInput
        view.onPause = onPause
    }
}
