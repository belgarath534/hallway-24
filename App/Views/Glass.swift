import SwiftUI

/// Liquid Glass on iOS 26 and later; the earlier look on iOS 17 and 18.
/// (Glass follows Reduce Transparency and Increase Contrast by itself.)
extension View {
    /// A floating panel: the captions, the status bar.
    @ViewBuilder func glassPanel(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }

    /// An everyday button: Listen again, items, Pause, Skip.
    @ViewBuilder func glassButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// The main button on a screen: the doors, Try again.
    @ViewBuilder func glassProminentButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
