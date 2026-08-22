import SwiftUI

/// The display's single source of visual truth.
///
/// Deliberately fixed to a dark palette in both appearances, unlike a normal
/// app that follows the system setting. This screen is on permanently, in a
/// hallway or a kitchen, and is looked at from several metres away: a white
/// rectangle glowing in a dark room at night is the wrong object, and the
/// system appearance of a device nobody unlocks is not a signal about the
/// room it's in. Contrast is tuned for distance, not for a phone at reading
/// range — hence the low-opacity surfaces and the very large type scale.
enum Theme {

    // MARK: - Palette

    enum Palette {
        static let background = Color(red: 0.043, green: 0.055, blue: 0.086)
        /// A card sitting on `background`.
        static let surface = Color.white.opacity(0.07)
        /// A card that needs to read as raised or selected.
        static let surfaceRaised = Color.white.opacity(0.13)
        static let hairline = Color.white.opacity(0.10)
        static let primaryText = Color.white
        static let secondaryText = Color.white.opacity(0.65)
        static let tertiaryText = Color.white.opacity(0.40)

        static func accent(for child: Child) -> Color {
            switch child.color {
            case .teal: return Color(red: 0.20, green: 0.83, blue: 0.75)
            case .violet: return Color(red: 0.68, green: 0.56, blue: 0.98)
            }
        }

        /// A wash of the child's colour, for tile backgrounds. Kept faint:
        /// the colour is an identity cue, not a surface.
        static func wash(for child: Child) -> LinearGradient {
            let accent = self.accent(for: child)
            return LinearGradient(
                colors: [accent.opacity(0.28), accent.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 12
        static let md: CGFloat = 20
        static let lg: CGFloat = 32
        static let xl: CGFloat = 48
    }

    // MARK: - Radius

    enum Radius {
        static let tile: CGFloat = 36
        static let card: CGFloat = 22
        static let pill: CGFloat = 999
    }

    // MARK: - Motion

    enum Motion {
        /// Screen changes. Slow enough to be legible as a transition from
        /// across the room rather than registering as a flicker.
        static let screen = Animation.spring(response: 0.5, dampingFraction: 0.86)
        static let press = Animation.spring(response: 0.28, dampingFraction: 0.72)
    }

    // MARK: - Type

    /// Rounded throughout — this is read by children, and the rounded face
    /// keeps large numerals from looking like a departures board.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// The standard card surface.
private struct CardModifier: ViewModifier {
    var padding: CGFloat
    var raised: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(raised ? Theme.Palette.surfaceRaised : Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = Theme.Spacing.md, raised: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, raised: raised))
    }
}

/// Scales a control down while it's held. Used by the big touch targets, so
/// a child gets a visible response even when the tap does nothing yet.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}
