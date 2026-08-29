import SwiftUI
import VexFoundation

/// Stands in for `ContentUnavailableView`, which is iOS 17+ while this app
/// targets iOS 16. Same role: a centered icon/title/message for an empty or
/// failed state.
struct ScoreUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
    }
}

/// The score, wrapped onto rows that scroll vertically.
///
/// Each row is its own `Canvas` inside a `LazyVStack`, so only the rows on
/// screen are engraved. Drawing the whole score into one tall canvas meant
/// every scroll frame rebuilt every stave, note, beam and slur in the piece,
/// which is what made scrolling stutter — and a cursor move redrew all of it
/// too. Now a cursor move repaints one row.
///
/// The canvas sits on a deliberately light "paper" surface in *both*
/// appearances. `VexCanvas` is a transparent SwiftUI `Canvas` and
/// VexFoundation engraves in black, so on a dark background the score would
/// render invisible. Treating the staff as paper — which is what sheet music
/// is — fixes that without restyling every stave and note for a second ink
/// palette.
struct ScoreCanvasView: View {
    let score: Score
    let currentPlayableIndex: Int
    /// Called with the playable-note index when the score is tapped. Nil makes
    /// the score non-interactive, which is what the player tab wants.
    var onSelectNote: ((Int) -> Void)?
    /// Bars chosen for repeat practice, marked with a bracket at each end.
    var sectionMeasures: ClosedRange<Int>?
    var noteSize: ScoreRenderer.NoteSize = .medium
    /// Keep the row holding the cursor centred as playback moves.
    var autoScroll: Bool = false
    /// Printed as a tempo marking above the first system.
    var tempoBPM: Double?

    private var metrics: ScoreRenderer.Metrics { .init(noteSize: noteSize) }

    /// Invisible scroll targets spaced down each row.
    ///
    /// `ScrollViewReader` can only align to a *view*, so with one id per row
    /// the finest move auto-scroll can make is a whole row — nothing happens
    /// for a dozen notes and then the score lurches a full system. Laying
    /// several targets down each row lets the follow move in small steps that
    /// run into each other, which is what reads as smooth.
    private static let scrollAnchorsPerRow = 8

    /// Last anchor scrolled to, so repeat notes inside one step don't restart
    /// the animation on top of itself.
    @State private var scrollAnchor: String?

    private static func anchorID(row: Int, step: Int) -> String {
        "row-\(row)-step-\(step)"
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let rowCount = ScoreRenderer.rowCount(for: score, availableWidth: width, metrics: metrics)

            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: metrics.rowGap) {
                    ForEach(0..<max(1, rowCount), id: \.self) { rowIndex in
                        VexCanvas(width: width, height: metrics.rowHeight) { context in
                            context.clear()
                            ScoreRenderer.drawRow(
                                score: score,
                                rowIndex: rowIndex,
                                into: context,
                                availableWidth: width,
                                cursorPlayableIndex: currentPlayableIndex >= 0 ? currentPlayableIndex : nil,
                                sectionMeasures: sectionMeasures,
                                tempoBPM: tempoBPM,
                                metrics: metrics
                            )
                        }
                        .frame(width: width, height: metrics.rowHeight)
                        // Positioned with padding rather than `.offset`, which
                        // is a draw-time transform the scroll reader wouldn't
                        // see. `.id` goes on the 1pt marker itself, before the
                        // padding, so the scroll target is the marker and not
                        // the tall padded box around it.
                        .overlay(alignment: .topLeading) {
                            ZStack(alignment: .topLeading) {
                                ForEach(0..<Self.scrollAnchorsPerRow, id: \.self) { step in
                                    Color.clear
                                        .frame(width: 1, height: 1)
                                        .id(Self.anchorID(row: rowIndex, step: step))
                                        .padding(.top, Double(step)
                                                 * (metrics.rowHeight - 1)
                                                 / Double(Self.scrollAnchorsPerRow - 1))
                                }
                            }
                            .frame(width: 1, height: metrics.rowHeight, alignment: .topLeading)
                            .allowsHitTesting(false)
                        }
                        // Hit-testing runs off the same row arithmetic the
                        // renderer uses, so no formatted layout has to escape
                        // the draw closure. The tap's y is row-local, so it's
                        // offset back into score space first.
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let onSelectNote else { return }
                            let scoreY = metrics.topMargin
                                + Double(rowIndex) * (metrics.rowHeight + metrics.rowGap)
                                + location.y
                            guard let index = ScoreRenderer.playableIndex(
                                at: CGPoint(x: location.x, y: scoreY),
                                score: score,
                                availableWidth: width,
                                metrics: metrics
                            ) else { return }
                            onSelectNote(index)
                        }
                    }
                }
                .padding(.vertical, metrics.topMargin)
            }
            // Follow the cursor *through* its row, not just onto it. Aiming at
            // the sub-row anchor nearest the cursor means the score creeps up
            // by a fraction of a system every few notes and is already most of
            // the way to the next row when the cursor gets there — instead of
            // sitting still and then jumping a whole system at the line break.
            //
            // Anchored centre throughout, so the note being played stays around
            // mid-screen with context above and below.
            .onChange(of: currentPlayableIndex) { index in
                guard autoScroll, index >= 0 else { return }
                guard let position = ScoreRenderer.rowPosition(
                    forPlayableIndex: index,
                    score: score,
                    availableWidth: width,
                    metrics: metrics
                ) else { return }
                let step = Int((position.fraction * Double(Self.scrollAnchorsPerRow - 1)).rounded())
                let anchor = Self.anchorID(row: position.row, step: step)
                guard anchor != scrollAnchor else { return }
                scrollAnchor = anchor
                withAnimation(Theme.Motion.follow) {
                    proxy.scrollTo(anchor, anchor: .center)
                }
            }
            }
        }
        // Edge to edge, no card. Sheet music is a page, not a widget: framing
        // it in a rounded, shadowed card wasted width the notation needed and
        // made the score look like a component rather than something to read.
        .background(Theme.Palette.paper)
    }
}
