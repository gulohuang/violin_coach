import SwiftUI

/// Tab 1: a straightforward chromatic tuner. Shows the detected note, how
/// many cents sharp/flat it is as a needle, and a color that turns green
/// within `TunerViewModel.inTuneCentsThreshold` cents.
struct TunerView: View {
    @StateObject private var viewModel = TunerViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Text(viewModel.noteLabel)
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.hasSignal ? (viewModel.isInTune ? .green : .primary) : .secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: viewModel.noteLabel)

                Text(viewModel.frequencyLabel)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)

                CentsMeter(cents: viewModel.cents, hasSignal: viewModel.hasSignal, isInTune: viewModel.isInTune)
                    .frame(height: 60)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 16) {
                    Stepper(
                        "A4 = \(Int(viewModel.detector.a4Reference)) Hz",
                        value: $viewModel.detector.a4Reference,
                        in: 415...466,
                        step: 1
                    )
                    .padding(.horizontal, 32)

                    Button {
                        viewModel.toggleListening()
                    } label: {
                        Label(
                            viewModel.detector.isListening ? "Stop" : "Start Tuner",
                            systemImage: viewModel.detector.isListening ? "mic.slash.fill" : "mic.fill"
                        )
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.detector.isListening ? .red : .accentColor)
                    .padding(.horizontal, 32)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Tuner")
        }
        .onDisappear { viewModel.detector.stop() }
    }
}

private struct CentsMeter: View {
    let cents: Int
    let hasSignal: Bool
    let isInTune: Bool

    private var clampedCents: Double {
        Double(max(-50, min(50, cents)))
    }

    var body: some View {
        GeometryReader { geo in
            let midX = geo.size.width / 2
            let needleX = midX + (clampedCents / 50) * (geo.size.width / 2 - 12)

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 2)
                    .position(x: midX, y: geo.size.height / 2)
                if hasSignal {
                    Circle()
                        .fill(isInTune ? .green : .orange)
                        .frame(width: 20, height: 20)
                        .position(x: needleX, y: geo.size.height / 2)
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: needleX)
                }
            }
        }
    }
}

struct TunerView_Previews: PreviewProvider {
    static var previews: some View {
        TunerView()
    }
}
