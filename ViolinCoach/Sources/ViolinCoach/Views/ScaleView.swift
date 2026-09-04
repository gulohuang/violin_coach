import SwiftUI

/// Tab 2: scales. Choose a tonality and key; the scale is engraved and then
/// practised note by note with live pitch feedback.
///
/// Below the picker row this *is* the Practice tab — same `PracticeSessionView`,
/// same `PracticeViewModel` — so the hold clock, the gate between notes, the
/// matching standard, and the intonation bars above and below the cursor note
/// behave identically. The only difference is where the score came from.
struct ScaleView: View {
    @StateObject private var viewModel = ScaleViewModel()
    @StateObject private var practice = PracticeViewModel()

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.background.ignoresSafeArea())
                .navigationTitle("Scales")
        }
        .onDisappear {
            practice.stop()
            viewModel.stop()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            pickers
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)

            if let score = viewModel.score {
                PracticeSessionView(viewModel: practice, score: score)
            } else {
                Spacer()
            }
        }
        // Loading is keyed on the scale's identity, so changing key starts a
        // clean session and coming back to the same one keeps your place.
        .onAppear { loadCurrentScale() }
        .onChange(of: viewModel.scoreIdentity) { _ in loadCurrentScale() }
        // The synth and the microphone must never run together: playback would
        // sound straight into the detector and be graded as the player.
        .onChange(of: practice.isActive) { active in
            if active { viewModel.stop() }
        }
    }

    private func loadCurrentScale() {
        guard let score = viewModel.score else { return }
        practice.load(score: score, identity: viewModel.scoreIdentity)
    }

    /// Tonality, key, range and direction, plus a listen button.
    ///
    /// Menus rather than segmented controls: twelve keys and five tonalities
    /// don't fit across a phone, and these are chosen once at the start of a
    /// practice session rather than adjusted while playing.
    private var pickers: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Menu {
                    ForEach(viewModel.availableRoots) { root in
                        Button(root.label) { viewModel.select(root: root) }
                    }
                } label: {
                    chip(viewModel.root.label, icon: "key")
                }

                Menu {
                    ForEach(ScaleType.allCases) { type in
                        Button(type.label) { viewModel.select(type: type) }
                    }
                } label: {
                    chip(viewModel.type.label, icon: "music.quarternote.3")
                }

                Spacer(minLength: 0)

                // Hearing the scale before playing it is the point of this
                // button, so it's beside the choice rather than down with the
                // practice transport.
                Button {
                    practice.stop()
                    viewModel.play(tempoBPM: practice.tempoBPM)
                } label: {
                    Image(systemName: viewModel.isPlaying ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.Palette.cardSurface))
                        .foregroundStyle(viewModel.isPlaying ? Theme.Palette.stop : Theme.Palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isPlaying ? "Stop listening" : "Listen to the scale")
            }

            HStack(spacing: Theme.Spacing.sm) {
                Menu {
                    // The ceiling moves with the key: three octaves of G fits
                    // on the instrument, three of F♯ doesn't.
                    ForEach(1...viewModel.maximumOctaves, id: \.self) { count in
                        Button(count == 1 ? "1 octave" : "\(count) octaves") {
                            viewModel.select(octaves: count)
                        }
                    }
                } label: {
                    chip(viewModel.octaves == 1 ? "1 octave" : "\(viewModel.octaves) octaves",
                         icon: "arrow.up.and.down")
                }

                Menu {
                    ForEach(ScaleDirection.allCases) { direction in
                        Button(direction.label) { viewModel.select(direction: direction) }
                    }
                } label: {
                    chip(viewModel.direction.label, icon: "arrow.turn.up.right")
                }

                if let summary = viewModel.rangeSummary {
                    Text(summary)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func chip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Capsule().fill(Theme.Palette.cardSurface))
            .foregroundStyle(Color.primary)
    }
}

struct ScaleView_Previews: PreviewProvider {
    static var previews: some View {
        ScaleView()
    }
}
