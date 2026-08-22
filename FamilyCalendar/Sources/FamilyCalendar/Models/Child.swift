import Foundation

/// Which of the two accent palettes a child gets. Kept as a plain enum rather
/// than a `Color` so the Models layer stays free of SwiftUI — `Theme` resolves
/// it to real colors for both light and dark appearances.
public enum ChildColor: String, Sendable, CaseIterable {
    case teal
    case violet
}

/// One of the people whose calendar this display shows.
///
/// Children are compiled in rather than editable at runtime, deliberately:
/// this is a wall-mounted display for one family, and an editing UI is one
/// more thing a child could wander into. Adding a third child is a one-line
/// change to `everyone` below.
public struct Child: Identifiable, Hashable, Sendable {
    /// Stable key — used for view selection and as a dictionary key. Never
    /// shown, so renaming a child doesn't invalidate stored state.
    public let id: String
    public let name: String
    public let color: ChildColor
    /// SF Symbol shown on the child's tile on the lock screen. Chosen to be
    /// distinguishable at a glance from across a room, and by a child who
    /// can't reliably read their own name yet.
    public let symbol: String

    public init(id: String, name: String, color: ChildColor, symbol: String) {
        self.id = id
        self.name = name
        self.color = color
        self.symbol = symbol
    }
}

extension Child {
    public static let alfred = Child(id: "alfred", name: "Alfred", color: .teal, symbol: "sailboat.fill")
    public static let elliot = Child(id: "elliot", name: "Elliot", color: .violet, symbol: "airplane")

    /// Display order — also the left-to-right order you swipe through.
    public static let everyone: [Child] = [.alfred, .elliot]

    public static func child(id: String) -> Child? {
        everyone.first { $0.id == id }
    }

    /// The child shown to the left/right of this one when swiping, or nil at
    /// either end. Deliberately not wrapping: on a display with no labels for
    /// "where am I", looping back around is disorienting.
    public var previous: Child? {
        guard let i = Self.everyone.firstIndex(of: self), i > 0 else { return nil }
        return Self.everyone[i - 1]
    }

    public var next: Child? {
        guard let i = Self.everyone.firstIndex(of: self), i + 1 < Self.everyone.count else { return nil }
        return Self.everyone[i + 1]
    }
}
