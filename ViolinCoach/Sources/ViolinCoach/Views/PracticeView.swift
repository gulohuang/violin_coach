import SwiftUI

/// Tab 3: note-by-note practice. Shows the score with a cursor on the
/// expected note, listens to the mic, and gives live "too high"/"too low"/
/// "in tune" feedback — advancing to the next note automatically once
/// you've held the right pitch for a moment (see `PracticeViewModel`).
struct PracticeView: View {
    @StateObject private var viewModel = PracticeViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if let score = viewModel.score {
                    loaded(score: score)
                } else if let error = viewModel.loadError {
                    ScoreUnavailableView(title: "Couldn't load score", message: error)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Practice")
        }
        .onDisappear { viewModel.stop() }
    }

    private func loaded(score: Score) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                // Greedy: takes the height left over from the feedback card
                // and transport, and scrolls internally.
                ScoreCanvasView(
                    score: score,
                    currentPlayableIndex: viewModel.currentIndex,
                    onSelectNote: { viewModel.moveCursor(to: $0) },
                    sectionMeasures: viewModel.sectionMeasures,
                    noteSize: viewModel.noteSize,
                    autoScroll: viewModel.autoScroll,
                    tempoBPM: viewModel.tempoBPM
                )
                .frame(maxHeight: .infinity)

                ScoreControlsBar(
                    tempoBPM: $viewModel.tempoBPM,
                    noteSize: $viewModel.noteSize,
                    autoScroll: $viewModel.autoScroll,
                    defaultTempoBPM: score.tempoBPM
                )

                sectionBar
                ScoreProgressBar(
                    current: viewModel.currentIndex,
                    total: score.playableNotes.count
                )
            }

            FeedbackCard(
                isActive: viewModel.isActive,
                isComplete: viewModel.isComplete,
                direction: viewModel.direction,
                expectedNoteLabel: viewModel.expectedNoteLabel,
                holdProgress: viewModel.holdProgress,
                requiredHold: viewModel.requiredHold
            )

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
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
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
    let isActive: Bool
    let isComplete: Bool
    let direction: PitchDirection?
    let expectedNoteLabel: String
    /// 0...1 through the sustain required for this note.
    let holdProgress: Double
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
            } else if isActive {
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
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.Palette.idle.opacity(0.22))
                            Capsule()
                                .fill(Theme.Palette.inTune)
                                .frame(width: max(0, min(1, holdProgress)) * geo.size.width)
                        }
                    }
                    .frame(height: 6)

                    Text(String(format: "hold %.1fs", requiredHold))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Tap Start Practice to begin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: Theme.Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch direction {
        case .tooHigh: return "arrow.down"   // play *lower* to correct a sharp note
        case .tooLow: return "arrow.up"
        case .inTune: return "checkmark.circle.fill"
        case nil: return "waveform"
        }
    }

    private var statusText: String {
        switch direction {
        case .tooHigh: return "Too high"
        case .tooLow: return "Too low"
        case .inTune: return "In tune"
        case nil: return "Listening…"
        }
    }
}

struct PracticeView_Previews: PreviewProvider {
    static var previews: some View {
        PracticeView()
    }
}
