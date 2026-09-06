import SwiftUI

/// The practice screen itself: the score with a cursor, live intonation on the
/// note you're on, the controls, and the transport.
///
/// Split out of `PracticeView` so the Scale tab can practise a generated scale
/// through exactly the same surface. There is one implementation of the hold
/// meter, the gate between notes, the matching standard and the section
/// picker, and both tabs get it — the alternative was a second copy that would
/// drift from this one on the first change to either.
///
/// It takes the score explicitly rather than reading `viewModel.score` so the
/// host decides what "loaded" means: the Practice tab gates on the file it
/// pushed, the Scale tab on the scale currently selected.
struct PracticeSessionView: View {
    @ObservedObject var viewModel: PracticeViewModel
    let score: Score
    /// Extra controls the host tab wants folded into the hideable stack — the
    /// Fine Tune tab's parameter panel. `AnyView` rather than a generic so the
    /// common call site stays `PracticeSessionView(viewModel:score:)`; this is
    /// a controls bar, not a hot path.
    var extraControls: AnyView?
    /// Whether starting practice clears the controls off screen.
    ///
    /// True for Practice and Scale, where you want the whole screen for the
    /// music. False for Fine Tune, where the controls *are* the reason you're
    /// there — a tuning screen that hides its sliders the moment you start the
    /// thing being tuned is no use.
    var hidesControlsWhilePracticing = true

    /// Controls hide once practice starts, so the score gets the whole screen
    /// — you're reading music at that point, not adjusting settings. Tapping
    /// the score brings them back.
    @State private var showsControls = true

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                // Greedy: takes the height left over from the feedback card
                // and transport, and scrolls internally.
                ScoreCanvasView(
                    score: score,
                    currentPlayableIndex: viewModel.currentIndex,
                    // One gesture, two jobs, split by state: while practice is
                    // running a tap reveals or hides the controls, and while
                    // it's stopped a tap still moves the cursor. Adding a
                    // second gesture would have fought the first.
                    onSelectNote: { index in
                        if viewModel.isActive {
                            withAnimation(Theme.Motion.gentle) { showsControls.toggle() }
                        } else {
                            viewModel.moveCursor(to: index)
                        }
                    },
                    // Only while practising: outside a session the cursor is
                    // just a "you are here", and there's no pitch to grade.
                    cursorDeviation: viewModel.isActive ? viewModel.cursorDeviation : nil,
                    sectionMeasures: viewModel.sectionMeasures,
                    noteSize: viewModel.noteSize,
                    autoScroll: viewModel.autoScroll,
                    tempoBPM: viewModel.tempoBPM
                )
                .frame(maxHeight: .infinity)

                if showsControls {
                    ScoreControlsBar(
                        tempoBPM: $viewModel.tempoBPM,
                        noteSize: $viewModel.noteSize,
                        autoScroll: $viewModel.autoScroll,
                        defaultTempoBPM: score.tempoBPM
                    )
                    practiceBar
                    extraControls
                    ScoreProgressBar(
                        current: viewModel.currentIndex,
                        total: score.playableNotes.count
                    )
                }
            }

            // Feedback only exists while there's something to report — no
            // placeholder card sitting on screen telling you to press a button
            // that's right there.
            if viewModel.isActive || viewModel.isComplete {
                FeedbackCard(
                    isComplete: viewModel.isComplete,
                    isWaiting: viewModel.isWaitingForNextNote,
                    direction: viewModel.direction,
                    expectedNoteLabel: viewModel.expectedNoteLabel,
                    // A closure, not a value: the meter reads it fresh inside
                    // its own TimelineView, so the card doesn't need the view
                    // model to republish for the bar to move.
                    holdProgress: { viewModel.holdProgress },
                    requiredHold: viewModel.requiredHold
                )
            }

            if showsControls {
            Button {
                if viewModel.isActive {
                    viewModel.stop()
                } else {
                    viewModel.start()
                }
            } label: {
                Label(
                    viewModel.isActive ? "Stop" : (viewModel.isComplete ? "Practice Again" : "Start Practice"),
                    systemImage: viewModel.isActive ? "mic.slash.fill" : "mic.fill"
                )
            }
            .buttonStyle(PrimaryActionButtonStyle(
                tint: viewModel.isActive ? Theme.Palette.stop : Theme.Palette.accent
            ))
            .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .animation(Theme.Motion.gentle, value: showsControls)
        .animation(Theme.Motion.gentle, value: viewModel.isActive)
        // Starting practice clears the chrome; stopping brings it back, so the
        // Start button is never stranded behind a hidden bar.
        .onChange(of: viewModel.isActive) { active in
            guard hidesControlsWhilePracticing else { return }
            withAnimation(Theme.Motion.gentle) { showsControls = !active }
        }
        // Arriving on a screen shows its controls, whatever state the last
        // session left them in.
        .onAppear {
            showsControls = hidesControlsWhilePracticing ? !viewModel.isActive : true
        }
        .overlay(alignment: .bottom) {
            // Stopping must never be more than one tap away. The controls fade
            // when practice starts, which used to leave Stop reachable only by
            // tapping the score first — two taps, and the second one not
            // obvious. So the hidden state keeps its own Stop button, and the
            // caption that used to sit here rides along with it.
            if viewModel.isActive && !showsControls {
                VStack(spacing: 4) {
                    Button {
                        viewModel.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Capsule().fill(Theme.Palette.stop))
                            .shadow(color: Theme.Palette.stop.opacity(0.35), radius: 8, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)

                    Text("Tap the score for controls")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, Theme.Spacing.md)
                .transition(.opacity)
            }
        }
    }

    /// The practice-only row: which bars to drill, and how strict the pitch
    /// match is. Neither belongs in `ScoreControlsBar` — that one is shared
    /// with the player tab, which has nothing to grade.
    private var practiceBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionBar
            toleranceButton
        }
    }

    /// Pitch-matching standard. A `Menu` rather than a segmented control: four
    /// names plus their cent windows don't fit across a phone, and this is a
    /// set-once setting rather than something toggled mid-piece.
    private var toleranceButton: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Menu {
                ForEach(PracticeViewModel.MatchTolerance.allCases) { level in
                    Button("\(level.label)  ±\(Int(level.cents))¢") {
                        viewModel.select(matchTolerance: level)
                    }
                }
            } label: {
                Label("Matching: \(viewModel.matchToleranceLabel)", systemImage: "target")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Capsule().fill(Theme.Palette.cardSurface))
            }
            .buttonStyle(.plain)

            Text("±\(Int(viewModel.currentCentsTolerance)) cents")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    /// Section picker. Selecting is two taps on the score, so the button only
    /// arms and disarms that mode — and doubles as the way to clear a section
    /// once one is set.
    private var sectionBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                viewModel.toggleSectionSelection()
            } label: {
                Label(sectionButtonTitle, systemImage: sectionButtonIcon)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        Capsule().fill(
                            viewModel.isSelectingSection
                                ? Theme.Palette.accent.opacity(0.16)
                                : Theme.Palette.cardSurface
                        )
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isSelectingSection ? Theme.Palette.accent : .primary)

            if let label = viewModel.sectionLabel {
                Text(viewModel.loopCount > 0 ? "\(label) · loop \(viewModel.loopCount + 1)" : label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
            } else if viewModel.isSelectingSection {
                Text(viewModel.pendingSectionStart == nil
                     ? "Tap the first bar"
                     : "Tap the last bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .animation(Theme.Motion.gentle, value: viewModel.isSelectingSection)
        .animation(Theme.Motion.gentle, value: viewModel.sectionMeasures)
    }

    private var sectionButtonTitle: String {
        if viewModel.isSelectingSection { return "Cancel" }
        return viewModel.sectionMeasures == nil ? "Select Section" : "Whole Piece"
    }

    private var sectionButtonIcon: String {
        if viewModel.isSelectingSection { return "xmark" }
        return viewModel.sectionMeasures == nil ? "square.dashed" : "arrow.counterclockwise"
    }
}

/// Live pitch feedback. Direction is carried by an arrow, a word, *and*
/// position — never by color alone, so the red/green signal at the heart of
/// this screen still works for colorblind players.
private struct FeedbackCard: View {
    let isComplete: Bool
    /// Inside the gap after a completed note, when nothing is being graded yet.
    let isWaiting: Bool
    let direction: PitchDirection?
    let expectedNoteLabel: String
    /// 0...1 through the sustain required for this note, read on demand.
    ///
    /// `@MainActor` because it reads main-actor state and is called from the
    /// `TimelineView` below, which is main-actor too — the annotation is what
    /// lets the compiler see that rather than take it on trust.
    let holdProgress: @MainActor () -> Double
    let requiredHold: TimeInterval

    private var accent: Color {
        switch direction {
        case .inTune: return Theme.Palette.inTune
        case .tooHigh, .tooLow: return Theme.Palette.outOfTune
        case nil: return Theme.Palette.idle
        }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if isComplete {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Palette.inTune)
                Text("Piece complete")
                    .font(.title3.weight(.semibold))
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Play")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(expectedNoteLabel)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .animation(Theme.Motion.gentle, value: expectedNoteLabel)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: symbolName)
                        .font(.title3.weight(.bold))
                    Text(statusText)
                        .font(.headline)
                }
                .foregroundStyle(accent)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(
                    Capsule().fill(accent.opacity(0.12))
                )
                .animation(Theme.Motion.gentle, value: direction)

                // How much of the note's length still has to be sustained.
                // Without this, waiting out a half note is indistinguishable
                // from the app having stopped responding.
                VStack(spacing: Theme.Spacing.xs) {
                    // The one thing on this screen that has to repaint
                    // continuously, and now the only thing that does. A
                    // TimelineView redraws this bar on its own schedule
                    // without the view model republishing, which is what used
                    // to drag every other view — the score, the controls, the
                    // Fine Tune sliders — along with it twenty times a second.
                    TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.Palette.idle.opacity(0.22))
                                Capsule()
                                    .fill(Theme.Palette.inTune)
                                    .frame(width: max(0, min(1, holdProgress())) * geo.size.width)
                            }
                        }
                    }
                    .frame(height: 6)

                    Text(String(format: "hold %.1fs", requiredHold))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: Theme.Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        // The gap between notes reads as unresponsiveness unless it says so.
        if isWaiting { return "hourglass" }
        switch direction {
        case .tooHigh: return "arrow.down"   // play *lower* to correct a sharp note
        case .tooLow: return "arrow.up"
        case .inTune: return "checkmark.circle.fill"
        case nil: return "waveform"
        }
    }

    private var statusText: String {
        if isWaiting { return "Next note…" }
        switch direction {
        case .tooHigh: return "Too high"
        case .tooLow: return "Too low"
        case .inTune: return "In tune"
        case nil: return "Listening…"
        }
    }
}
