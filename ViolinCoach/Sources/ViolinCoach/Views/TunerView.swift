import SwiftUI

/// Tab 1: a chromatic tuner. An arc gauge shows how many cents sharp or flat
/// the pitch is, and the four open strings can be tapped to lock the gauge to
/// one of them instead of auto-detecting the nearest chromatic note.
struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    Text(viewModel.targetLabel ?? "Chromatic · nearest note")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(viewModel.targetLabel == nil ? .secondary : Theme.Palette.accent)
                        .animation(Theme.Motion.gentle, value: viewModel.targetMIDI)

                    TunerGauge(
                        cents: viewModel.cents,
                        hasSignal: viewModel.hasSignal,
                        isInTune: viewModel.isInTune,
                        referenceLabel: viewModel.referenceLabel,
                        referenceFrequencyLabel: viewModel.referenceFrequencyLabel,
                        frequencyLabel: viewModel.frequencyLabel
                    )

                    OpenStringRow(
                        strings: TunerViewModel.openStrings,
                        selectedMIDI: viewModel.targetMIDI,
                        nearestMIDI: viewModel.nearestStringMIDI,
                        onSelect: { viewModel.selectString(midi: $0) }
                    )

                    InputLevelBar(
                        level: viewModel.level,
                        thresholdLevel: viewModel.sensitivityThresholdLevel,
                        isAboveThreshold: viewModel.level >= viewModel.sensitivityThresholdLevel
                    )

                    sensitivityCard

                    referenceCard

                    Button {
                        viewModel.toggleListening()
                    } label: {
                        Label(
                            viewModel.isListening ? "Stop" : "Start Tuner",
                            systemImage: viewModel.isListening ? "mic.slash.fill" : "mic.fill"
                        )
                    }
                    .buttonStyle(PrimaryActionButtonStyle(
                        tint: viewModel.isListening ? Theme.Palette.stop : Theme.Palette.accent
                    ))
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Tuner")
        }
        .onDisappear { viewModel.stop() }
    }

    private var sensitivityCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Detection sensitivity")
                .font(.subheadline.weight(.medium))

            Picker("Detection sensitivity", selection: Binding(
                get: { viewModel.sensitivity },
                set: { viewModel.sensitivity = $0 }
            )) {
                ForEach(PitchDetector.Sensitivity.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.sensitivity.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(Theme.Motion.gentle, value: viewModel.sensitivity)
        }
        .card()
    }

    private var referenceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Reference pitch")
                    .font(.subheadline.weight(.medium))
                Text("A4 = \(Int(viewModel.a4Reference)) Hz")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(
                "",
                value: $viewModel.a4Reference,
                in: 415...466,
                step: 1
            )
            .labelsHidden()
        }
        .card()
    }
}

// MARK: - Gauge

/// A 240° arc gauge reading -50 to +50 cents left to right, with the
/// reference pitch named in the middle and a needle pointing at the detected
/// pitch: left of centre is flat, right is sharp, straight up is in tune.
private struct TunerGauge: View {
    let cents: Int
    let hasSignal: Bool
    let isInTune: Bool
    /// The pitch being measured against — sits in the middle of the dial.
    let referenceLabel: String
    let referenceFrequencyLabel: String
    /// Frequency actually detected, which the needle represents.
    let frequencyLabel: String

    /// The arc spans 240°, starting at 150° and sweeping clockwise to 30°.
    /// Angles follow SwiftUI's convention: 0° points right (3 o'clock) and
    /// increases clockwise, so 270° is straight up — the centre of the arc,
    /// and where a perfectly in-tune note reads.
    private let startAngle: Double = 150
    private let sweep: Double = 240
    /// Cents at each end of the arc. Readings beyond this peg the indicator at
    /// the end while the numeric readout keeps showing the true value — the
    /// arc stays at a useful fine-tuning resolution without misreporting how
    /// far off a badly out-of-tune string actually is.
    private let displayRange: Double = 50

    /// Height is set explicitly rather than derived from an aspect ratio. This
    /// view sits in a vertical ScrollView, which proposes a nil height; a
    /// GeometryReader has no ideal size of its own, so an aspect-ratio fit
    /// collapses to zero and the whole gauge silently disappears.
    private let gaugeHeight: CGFloat = 260

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
                scaleLabels(center: center, radius: radius, lineWidth: lineWidth)

                // The needle. Starts outside the hub so it never runs across
                // the reference pitch printed in the middle.
                if hasSignal {
                    NeedleShape(
                        progress: progress,
                        startAngle: startAngle,
                        sweep: sweep,
                        innerRatio: 0.52,
                        outerRatio: 0.94
                    )
                    .stroke(style: StrokeStyle(lineWidth: max(3, lineWidth * 0.28), lineCap: .round))
                    .foregroundStyle(indicatorColor)
                    .padding(lineWidth / 2)
                    .animation(Theme.Motion.responsive, value: progress)
                }

                readout
                    .position(x: geo.size.width / 2, y: side * 0.56)
            }
            .frame(width: geo.size.width, height: side)
        }
        .frame(height: gaugeHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var readout: some View {
        VStack(spacing: 2) {
            Text("REFERENCE")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.tertiary)

            // The reference pitch — what the needle is measured against.
            Text(referenceLabel)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(hasSignal ? (isInTune ? Theme.Palette.inTune : Color.primary) : .secondary)
                .animation(Theme.Motion.gentle, value: referenceLabel)

            if !referenceFrequencyLabel.isEmpty {
                Text(referenceFrequencyLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            // What the microphone actually picked up. Always on screen — it's
            // the raw measurement, and useful even with no clear note.
            Text(frequencyLabel.isEmpty ? "— Hz" : frequencyLabel)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            if hasSignal {
                Text(centsLabel)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(indicatorColor)
            }
        }
    }

    private var centsLabel: String {
        if isInTune { return "In tune" }
        return cents > 0 ? "+\(cents)¢ sharp" : "\(cents)¢ flat"
    }

    private var accessibilityDescription: String {
        guard hasSignal else { return "Tuner. No pitch detected." }
        if isInTune { return "Reference \(referenceLabel). In tune at \(frequencyLabel)." }
        return "Reference \(referenceLabel). \(frequencyLabel), \(abs(cents)) cents \(cents > 0 ? "sharp" : "flat")."
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

    /// -50 / 0 / +50 printed just inside the arc, so the span the needle
    /// covers is readable rather than implied.
    private func scaleLabels(center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> some View {
        let entries: [(fraction: Double, text: String)] = [
            (0, "-50"), (0.5, "0"), (1, "+50"),
        ]
        return ForEach(entries, id: \.text) { entry in
            Text(entry.text)
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .position(pointOnArc(
                    progress: entry.fraction,
                    center: center,
                    radius: radius - lineWidth * 1.25
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

/// The gauge needle: a radial segment pointing at `progress` along the arc.
///
/// It runs from `innerRatio` to `outerRatio` of the radius rather than from
/// the hub, so it sweeps the scale without crossing the reference pitch
/// printed in the middle of the dial.
private struct NeedleShape: Shape {
    var progress: Double
    var startAngle: Double
    var sweep: Double
    var innerRatio: Double
    var outerRatio: Double

    /// Animating `progress` is what makes the needle swing rather than jump.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: side / 2)
        let radius = side / 2
        let radians = (startAngle + sweep * progress) * .pi / 180
        let dx = cos(radians)
        let dy = sin(radians)

        var path = Path()
        path.move(to: CGPoint(
            x: center.x + dx * radius * innerRatio,
            y: center.y + dy * radius * innerRatio
        ))
        path.addLine(to: CGPoint(
            x: center.x + dx * radius * outerRatio,
            y: center.y + dy * radius * outerRatio
        ))
        return path
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

// MARK: - Input level

/// Microphone input level, with a tick marking where the current sensitivity
/// setting's gate falls. The marker is the point: a bar that shows sound
/// arriving while the tuner reports nothing is confusing until you can see
/// that the signal is landing below the threshold.
private struct InputLevelBar: View {
    let level: Double
    let thresholdLevel: Double
    let isAboveThreshold: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Label("Input level", systemImage: "mic.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isAboveThreshold ? "Detecting" : "Too quiet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isAboveThreshold ? Theme.Palette.inTune : .secondary)
                    .animation(Theme.Motion.gentle, value: isAboveThreshold)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Palette.idle.opacity(0.22))

                    Capsule()
                        .fill(isAboveThreshold ? Theme.Palette.inTune : Theme.Palette.idle.opacity(0.6))
                        .frame(width: max(0, min(1, level)) * geo.size.width)
                        .animation(Theme.Motion.responsive, value: level)

                    // Threshold marker
                    Rectangle()
                        .fill(Theme.Palette.outOfTune)
                        .frame(width: 2)
                        .offset(x: max(0, min(1, thresholdLevel)) * geo.size.width - 1)
                        .animation(Theme.Motion.gentle, value: thresholdLevel)
                }
            }
            .frame(height: 10)
        }
        .card(padding: Theme.Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue(
            isAboveThreshold
                ? "\(Int(level * 100)) percent, above the detection threshold"
                : "\(Int(level * 100)) percent, below the detection threshold"
        )
    }
}

// MARK: - Open strings

/// The four open violin strings as buttons. Tapping one locks the gauge to
/// that pitch; tapping it again returns to chromatic auto-detect. In auto
/// mode the string nearest the detected pitch is hinted, so the row still
/// orients you without a selection.
private struct OpenStringRow: View {
    let strings: [TunerViewModel.OpenString]
    let selectedMIDI: Int?
    let nearestMIDI: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(strings) { string in
                let isSelected = string.midi == selectedMIDI
                let isNearest = selectedMIDI == nil && string.midi == nearestMIDI

                Button {
                    onSelect(string.midi)
                } label: {
                    Text(string.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : (isNearest ? Theme.Palette.accent : .secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(isSelected ? Theme.Palette.accent : Theme.Palette.cardSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .strokeBorder(Theme.Palette.accent, lineWidth: isNearest ? 1.5 : 0)
                        )
                }
                .buttonStyle(.plain)
                .animation(Theme.Motion.gentle, value: isSelected)
                .accessibilityLabel("\(string.name) string")
                .accessibilityHint(isSelected ? "Selected. Tap to return to chromatic tuning." : "Tap to tune to this string.")
            }
        }
    }
}

struct TunerView_Previews: PreviewProvider {
    static var previews: some View {
        TunerView()
    }
}
