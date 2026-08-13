import SwiftUI
import UIKit

/// The app's single source of visual truth: colors, spacing, corner radii and
/// motion. Views should reach for these rather than literal values, so the
/// look can be changed in one place.
///
/// Colors are defined with `UIColor`'s dynamic-provider initializer rather
/// than an asset catalog. Both appearances live in one line of Swift here,
/// which is easier to review in a diff than a directory of `Contents.json`
/// files, and avoids a whole class of "color not found at runtime" bugs that
/// only show up once the app is running.
enum Theme {

    // MARK: - Palette

    enum Palette {
        /// Brand accent — used for controls, the score cursor, and the tab bar tint.
        static let accent = dynamic(
            light: UIColor(red: 0.20, green: 0.36, blue: 0.85, alpha: 1),
            dark: UIColor(red: 0.42, green: 0.58, blue: 1.00, alpha: 1)
        )

        /// Pitch is within tolerance.
        static let inTune = dynamic(
            light: UIColor(red: 0.10, green: 0.62, blue: 0.35, alpha: 1),
            dark: UIColor(red: 0.28, green: 0.82, blue: 0.50, alpha: 1)
        )

        /// Pitch is off — deliberately one color for both sharp and flat.
        /// Direction is conveyed by the gauge position and an arrow/word, never
        /// by hue alone, so the feedback survives colorblindness.
        static let outOfTune = dynamic(
            light: UIColor(red: 0.85, green: 0.52, blue: 0.10, alpha: 1),
            dark: UIColor(red: 1.00, green: 0.68, blue: 0.25, alpha: 1)
        )

        /// A destructive/stop affordance.
        static let stop = dynamic(
            light: UIColor(red: 0.83, green: 0.24, blue: 0.24, alpha: 1),
            dark: UIColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1)
        )

        /// No signal / inactive track.
        static let idle = Color(uiColor: .tertiaryLabel)

        /// Page background behind cards.
        static let background = Color(uiColor: .systemGroupedBackground)

        /// Card surface sitting on `background`.
        static let cardSurface = Color(uiColor: .secondarySystemGroupedBackground)

        /// Sheet-music paper. Intentionally light in *both* appearances: the
        /// notation VexFoundation draws is black, and `VexCanvas` is a
        /// transparent SwiftUI `Canvas`, so without a light surface behind it
        /// the score is invisible in dark mode. Real sheet music is paper —
        /// keeping it that way sidesteps theming every stave and note.
        static let paper = Color(red: 0.99, green: 0.99, blue: 0.98)

        /// Score cursor wash. A CSS string because VexFoundation's
        /// `RenderContext` takes CSS colors, not SwiftUI `Color`s. Kept in
        /// sync with `accent` by hand — the render context has no access to
        /// the SwiftUI environment, so it can't resolve a dynamic color.
        /// Always drawn over `paper`, so it only needs a light-mode value.
        static let scoreCursorCSS = "rgba(52, 92, 217, 0.22)"

        private static func dynamic(light: UIColor, dark: UIColor) -> Color {
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            })
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Radius

    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 14
        /// Large enough to fully round any control we use.
        static let pill: CGFloat = 999
    }

    // MARK: - Motion

    enum Motion {
        /// For values that track live input (the tuner needle) — quick, barely damped.
        static let responsive = Animation.spring(response: 0.28, dampingFraction: 0.72)
        /// For state changes the user reads (feedback words, transport state).
        static let gentle = Animation.spring(response: 0.42, dampingFraction: 0.85)
    }
}

// MARK: - Card

private struct CardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Palette.cardSurface)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

extension View {
    /// Wraps the view in the app's standard card surface.
    func card(padding: CGFloat = Theme.Spacing.md) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Buttons

/// The app's primary action button: full-width, tinted, with a pressed state.
/// Replaces the repeated `.borderedProminent` + `.tint` + `.padding` stacks
/// that were duplicated across the tabs.
struct PrimaryActionButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(tint)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.Motion.responsive, value: configuration.isPressed)
    }
}

/// A large circular transport control (play/stop), for the score player.
struct CircularTransportButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.accent
    var diameter: CGFloat = 76

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.36, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(tint))
            .shadow(color: tint.opacity(0.35), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.Motion.responsive, value: configuration.isPressed)
    }
}
