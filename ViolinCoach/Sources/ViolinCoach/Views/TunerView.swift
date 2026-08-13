import SwiftUI

/// Tab 1: a chromatic tuner. An arc gauge shows how many cents sharp or flat
/// the detected pitch is, the detected note sits in the middle of it, and a
/// row of the four open violin strings highlights whichever one you're
/// nearest to.
struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    TunerGauge(
                        cents: viewModel.cents,
                        hasSignal: viewModel.hasSignal,
                        isInTune: viewModel.isInTune,
                        noteLabel: viewModel.noteLabel,
                        frequencyLabel: viewModel.frequencyLabel
                    )
                    .padding(.top, Theme.Spacing.md)

                    OpenStringRow(detectedMIDI: viewModel.detector.note?.midi)

                    referenceCard

                    Button {
                        viewModel.toggleListening()
                    } label: {
                        Label(
                            viewModel.detector.isListening ? "Stop" : "Start Tuner",
                            systemImage: viewModel.detector.isListening ? "mic.slash.fill" : "mic.fill"
                        )
                    }
                    .buttonStyle(PrimaryActionButtonStyle(
                        tint: viewModel.detector.isListening ? Theme.Palette.stop : Theme.Palette.accent
                    ))
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Tuner")
        }
        .onDisappear { viewModel.detector.stop() }
    }

    private var referenceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Reference pitch")
                    .font(.subheadline.weight(.medium))
                Text("A4 = \(Int(viewModel.detector.a4Reference)) Hz")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(
                "",
                value: $viewModel.detector.a4Reference,
                in: 415...466,
                step: 1
            )
            .labelsHidden()
        }
        .card()
    }
}

// MARK: - Gauge

/// A 240° arc gauge. Cents map left-to-right across the arc, with 0 at the
/// top; the detected note and frequency sit in the middle.
private struct TunerGauge: View {
    let cents: Int
    let hasSignal: Bool
    let isInTune: Bool
    let noteLabel: String
    let frequencyLabel: String

    /// The arc spans 240°, starting at 150° and sweeping clockwise to 30°.
    /// Angles follow SwiftUI's convention: 0° points right (3 o'clock) and
    /// increases clockwise, so 270° is straight up — the centre of the arc,
    /// and where a perfectly in-tune note reads.
    private let startAngle: Double = 150
    private let sweep: Double = 240
    private let displayRange: Double = 50 // cents at each end of the arc

    /// Cents mapped onto 0...1 along the arc. Values beyond ±50 clamp to the ends.
    private var progress: Double {
        let clamped = max(-displayRange, min(displayRange, Double(cents)))
        return (clamped + displayRange) / (displayRange * 2)
    }

    private var indicatorColor: Color {
        guard hasSignal else { return Theme.Palette.idle }
        return isInTune ? Theme.Palette.inTune : Theme.Palette.outOfTune
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lineWidth = side * 0.075
            let radius = (side - lineWidth) / 2
            let center = CGPoint(x: geo.size.width / 2, y: side / 2)

            ZStack {
                // Track. Padded by half the stroke width so the stroke, which
                // straddles the path, stays inside the frame instead of clipping.
                ArcShape(startAngle: startAngle, sweep: sweep)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .foregroundStyle(Theme.Palette.idle.opacity(0.25))
                    .padding(lineWidth / 2)

                // Fill from centre out to the current reading, so the arc shows
                // both how far off you are and in which direction.
                if hasSignal {
                    ArcShape(
                        startAngle: startAngle + sweep * min(0.5, progress),
                        sweep: sweep * abs(progress - 0.5)
                    )
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .foregroundStyle(indicatorColor)
                    .padding(lineWidth / 2)
                    .animation(Theme.Motion.responsive, value: progress)
                }

                tickMarks(center: center, radius: radius, lineWidth: lineWidth)

                if hasSignal {
                    Circle()
                        .fill(indicatorColor)
                        .frame(width: lineWidth * 1.35, height: lineWidth * 1.35)
                        .position(pointOnArc(progress: progress, center: center, radius: radius))
                        .animation(Theme.Motion.responsive, value: progress)
                }

                readout
                    .position(x: geo.size.width / 2, y: side * 0.52)
            }
            .frame(width: geo.size.width, height: side)
        }
        .aspectRatio(1.15, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var readout: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(hasSignal ? noteLabel : "—")
                .font(.system(size: 68, weight: .bold, design: .rounded))
                .foregroundStyle(hasSignal ? (isInTune ? Theme.Palette.inTune : Color.primary) : .secondary)
                .animation(Theme.Motion.gentle, value: noteLabel)

            if hasSignal {
                Text(centsLabel)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(indicatorColor)
                Text(frequencyLabel)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Play a note")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var centsLabel: String {
        if isInTune { return "In tune" }
        return cents > 0 ? "+\(cents)¢ sharp" : "\(cents)¢ flat"
    }

    private var accessibilityDescription: String {
        guard hasSignal else { return "Tuner. No pitch detected." }
        if isInTune { return "\(noteLabel), in tune." }
        return "\(noteLabel), \(abs(cents)) cents \(cents > 0 ? "sharp" : "flat")."
    }

    private func tickMarks(center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> some View {
        // -50, -25, 0, +25, +50 cents. The centre tick is longer since it's
        // the one the player is aiming for.
        ForEach(0..<5, id: \.self) { i in
            let fraction = Double(i) / 4
            let isCentre = i == 2
            let length = lineWidth * (isCentre ? 0.9 : 0.5)
            // Rotate about the capsule's own centre first, then place it —
            // reversing these would spin the positioned view about the
            // parent's centre and fling the ticks off the arc.
            Capsule()
                .fill(isCentre ? Theme.Palette.inTune.opacity(0.7) : Theme.Palette.idle.opacity(0.5))
                .frame(width: 2.5, height: length)
                .rotationEffect(.degrees(startAngle + sweep * fraction + 90), anchor: .center)
                .position(pointOnArc(
                    progress: fraction,
                    center: center,
                    radius: radius + lineWidth * 0.85
                ))
        }
    }

    private func pointOnArc(progress: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let degrees = startAngle + sweep * progress
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )
    }
}

/// An arc of `sweep` degrees beginning at `startAngle`, drawn clockwise.
/// Angles use SwiftUI's convention (0° = 3 o'clock, increasing clockwise).
private struct ArcShape: Shape {
    var startAngle: Double
    var sweep: Double

    /// Lets the fill arc animate smoothly as the reading moves.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngle, sweep) }
        set {
            startAngle = newValue.first
            sweep = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: side / 2)
        // Insets by half the eventual stroke width are handled by the caller
        // sizing the frame; use the full radius here.
        let radius = side / 2
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(startAngle + sweep),
            clockwise: false
        )
        return path
    }
}

// MARK: - Open strings

/// The four open violin strings, highlighting whichever is closest to the
/// detected pitch — quick orientation while tuning string by string.
private struct OpenStringRow: View {
    let detectedMIDI: Int?

    private static let strings: [(name: String, midi: Int)] = [
        ("G", 55), ("D", 62), ("A", 69), ("E", 76),
    ]

    /// Nearest open string, but only when the pitch is within three semitones
    /// of one — otherwise nothing is highlighted rather than guessing.
    private var nearestMIDI: Int? {
        guard let detectedMIDI else { return nil }
        let nearest = Self.strings.min { abs($0.midi - detectedMIDI) < abs($1.midi - detectedMIDI) }
        guard let nearest, abs(nearest.midi - detectedMIDI) <= 3 else { return nil }
        return nearest.midi
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Self.strings, id: \.midi) { string in
                let isActive = string.midi == nearestMIDI
                Text(string.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isActive ? Color.white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(isActive ? Theme.Palette.accent : Theme.Palette.cardSurface)
                    )
                    .animation(Theme.Motion.gentle, value: isActive)
                    .accessibilityLabel("\(string.name) string\(isActive ? ", nearest" : "")")
            }
        }
    }
}

struct TunerView_Previews: PreviewProvider {
    static var previews: some View {
        TunerView()
    }
}
