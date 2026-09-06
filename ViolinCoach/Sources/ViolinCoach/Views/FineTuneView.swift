import AVFoundation
import SwiftUI

/// Tab 5: the Practice tab with every detection constant exposed as a slider.
///
/// Same folder, same score, same `PracticeSessionView` — so what you feel here
/// is exactly what Practice will feel like, which is the only reason the
/// numbers you land on are worth anything. The parameter panel folds into the
/// session's own hideable controls stack rather than a sheet, so the score,
/// the feedback card and the sliders are all on screen while you play.
///
/// Changes are shared and persisted (`TuningStore`), so tuning here really does
/// retune Practice and Scale. That's the point — a tuning screen whose values
/// went nowhere would be an elaborate no-op. Reset restores the shipped
/// defaults exactly.
struct FineTuneView: View {
    @StateObject private var viewModel = PracticeViewModel()
    @StateObject private var library = ScoreLibraryViewModel()
    @ObservedObject private var tuning = TuningStore.shared

    var body: some View {
        NavigationStack {
            ScoreLibraryView(library: library, prompt: "Choose a score to tune against")
                .navigationTitle("Fine Tune")
                .background(Theme.Palette.background.ignoresSafeArea())
                .navigationDestination(for: ScoreEntry.self) { entry in
                    session(for: entry)
                }
        }
        .onDisappear { viewModel.stop() }
    }

    private func session(for entry: ScoreEntry) -> some View {
        Group {
            if let score = viewModel.score, viewModel.isLoaded(entry) {
                PracticeSessionView(
                    viewModel: viewModel,
                    score: score,
                    extraControls: AnyView(TuningPanel(tuning: tuning)),
                    // The sliders have to stay put while you play — moving one
                    // and hearing the difference immediately is the whole
                    // method here.
                    hidesControlsWhilePracticing: false
                )
            } else if let error = viewModel.loadError, viewModel.isLoaded(entry) {
                ScoreUnavailableView(title: "Couldn't load score", message: error)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background.ignoresSafeArea())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load(entry) }
        .onDisappear { viewModel.stop() }
    }
}

/// Every tunable constant, grouped the way the detection chain runs: what
/// reaches the analysis, how close counts, how long you must hold, and how
/// long the gate stays shut afterwards.
private struct TuningPanel: View {
    @ObservedObject var tuning: TuningStore

    /// The real hardware rate, so the analyses-per-second readout beside the
    /// buffer slider is the true figure for this device rather than an
    /// assumed 44.1 or 48 kHz.
    private var sampleRate: Double {
        let rate = AVAudioSession.sharedInstance().sampleRate
        return rate > 0 ? rate : 48_000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            header

            // Bounded and scrollable: twelve sliders is more than fits beside
            // a score, and the score is the half you need to keep watching.
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    group("Detection") {
                        bufferSlider
                        windowSlider
                        slider("Min clarity", value: $tuning.parameters.minimumClarity,
                               range: 0.05...0.95, step: 0.01,
                               format: { String(format: "%.2f", $0) },
                               note: "How periodic a signal must be to count as a note.")
                        slider("Min RMS", value: $tuning.parameters.minimumRMS,
                               range: 0.0002...0.02, step: 0.0002,
                               format: { String(format: "%.4f", $0) },
                               note: "Amplitude floor, an early-out before analysis.")
                    }

                    group("Matching") {
                        slider("Cents window", value: $tuning.parameters.centsTolerance,
                               range: 5...60, step: 1,
                               format: { "±\(Int($0))¢" },
                               note: "50 is half a semitone; 10 is inside a normal vibrato.")
                    }

                    group("Hold") {
                        slider("Hold fraction", value: $tuning.parameters.holdFraction,
                               range: 0...1.5, step: 0.05,
                               format: { String(format: "%.2f×", $0) },
                               note: "Share of the written duration you must sustain.")
                        slider("Min hold", value: $tuning.parameters.minimumHold,
                               range: 0.05...1.0, step: 0.01, format: seconds)
                        slider("Max hold", value: $tuning.parameters.maximumHold,
                               range: 0.3...3.0, step: 0.05, format: seconds)
                        slider("Hold grace", value: $tuning.parameters.holdGrace,
                               range: 0...0.5, step: 0.01, format: seconds,
                               note: "How long a dropped reading is forgiven.")
                    }

                    group("Gate between notes") {
                        slider("Gate fraction", value: $tuning.parameters.refractoryFraction,
                               range: 0...1.0, step: 0.05,
                               format: { String(format: "%.2f×", $0) },
                               note: "Share of the finished note's length to ignore input for.")
                        slider("Min gate", value: $tuning.parameters.minimumRefractory,
                               range: 0...0.3, step: 0.01, format: seconds)
                        slider("Max gate", value: $tuning.parameters.maximumRefractory,
                               range: 0.1...1.5, step: 0.05, format: seconds)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
            .frame(maxHeight: 300)
        }
        .card(padding: Theme.Spacing.md)
    }

    private var header: some View {
        HStack {
            Label("Tuning", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Reset") { tuning.reset() }
                .font(.caption.weight(.medium))
                .disabled(tuning.isDefault)
        }
    }

    // MARK: - Buffer and window

    /// Stepped over powers of two rather than continuous: CoreAudio deals in
    /// them, and anything between is rounded by the system anyway. The slider
    /// therefore moves over *indices* into the choice list.
    private var bufferSlider: some View {
        let choices = TuningParameters.bufferSizeChoices
        let index = choices.firstIndex(of: tuning.parameters.tapBufferFrames) ?? 3
        let frames = tuning.parameters.tapBufferFrames
        let period = Double(frames) / sampleRate
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Buffer size").font(.caption.weight(.medium))
                Spacer()
                Text("\(frames) frames")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.accent)
            }
            Slider(
                value: Binding(
                    get: { Double(index) },
                    set: { tuning.parameters.tapBufferFrames = choices[clamp(Int($0.rounded()), choices.count)] }
                ),
                in: 0...Double(choices.count - 1),
                step: 1
            )
            // The number that actually matters: bigger buffer, fewer readings.
            Text(String(format: "%.1f ms per buffer · %.1f analyses/sec · restarts the mic",
                        period * 1000, 1 / period))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var windowSlider: some View {
        let choices = TuningParameters.analysisWindowChoices
        let index = choices.firstIndex(of: tuning.parameters.analysisWindow) ?? 2
        let window = tuning.parameters.analysisWindow
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Analysis window").font(.caption.weight(.medium))
                Spacer()
                Text("\(window) samples")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.accent)
            }
            Slider(
                value: Binding(
                    get: { Double(index) },
                    set: { tuning.parameters.analysisWindow = choices[clamp(Int($0.rounded()), choices.count)] }
                ),
                in: 0...Double(choices.count - 1),
                step: 1
            )
            Text(String(format: "%.1f ms of audio per reading · anything past the buffer is unused",
                        Double(window) / sampleRate * 1000))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Building blocks

    private func clamp(_ index: Int, _ count: Int) -> Int {
        max(0, min(count - 1, index))
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        note: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.accent)
            }
            Slider(value: value, in: range, step: step)
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FineTuneView_Previews: PreviewProvider {
    static var previews: some View {
        FineTuneView()
    }
}
