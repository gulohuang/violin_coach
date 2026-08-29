import SwiftUI

/// Tempo, note size and auto-scroll controls, shared by the Score Player and
/// Practice tabs.
///
/// Each control is a chip that expands its editor inline when tapped, and only
/// one is open at a time. On a phone there isn't room to leave a tempo slider
/// and a size picker permanently on screen next to the score, and both are
/// set-and-forget settings rather than things adjusted constantly.
struct ScoreControlsBar: View {
    @Binding var tempoBPM: Double
    @Binding var noteSize: ScoreRenderer.NoteSize
    @Binding var autoScroll: Bool
    /// The score's own marking, offered as a reset target.
    let defaultTempoBPM: Double

    private enum Editor { case tempo, size }
    @State private var open: Editor?

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                chip(
                    title: "\(Int(tempoBPM)) BPM",
                    icon: "metronome",
                    isOn: open == .tempo
                ) { toggle(.tempo) }

                chip(
                    title: noteSize.label,
                    icon: "textformat.size",
                    isOn: open == .size
                ) { toggle(.size) }

                chip(
                    title: "Auto-scroll",
                    icon: autoScroll ? "checkmark.circle.fill" : "circle",
                    isOn: autoScroll
                ) {
                    withAnimation(Theme.Motion.gentle) { autoScroll.toggle() }
                }

                Spacer(minLength: 0)
            }

            if open == .tempo { tempoEditor }
            if open == .size { sizeEditor }
        }
        .animation(Theme.Motion.gentle, value: open)
    }

    private var tempoEditor: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack {
                Text("40")
                Slider(value: $tempoBPM, in: 40...200, step: 1)
                Text("200")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Text("\(Int(tempoBPM)) BPM")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                Spacer()
                Button("Reset to \(Int(defaultTempoBPM))") {
                    withAnimation(Theme.Motion.gentle) { tempoBPM = defaultTempoBPM }
                }
                .font(.caption)
                .disabled(Int(tempoBPM) == Int(defaultTempoBPM))
            }
        }
        .card(padding: Theme.Spacing.md)
        .transition(.opacity)
    }

    private var sizeEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // A slider rather than five labelled segments: the labels don't fit
            // across a phone, and size is an ordered scale.
            let options = ScoreRenderer.NoteSize.allCases
            Slider(
                value: Binding(
                    get: { Double(options.firstIndex(of: noteSize) ?? 2) },
                    set: { noteSize = options[max(0, min(options.count - 1, Int($0.rounded())))] }
                ),
                in: 0...Double(options.count - 1),
                step: 1
            )
            HStack {
                Text(options.first?.label ?? "")
                Spacer()
                Text(noteSize.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Palette.accent)
                Spacer()
                Text(options.last?.label ?? "")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .card(padding: Theme.Spacing.md)
        .transition(.opacity)
    }

    private func toggle(_ editor: Editor) {
        withAnimation(Theme.Motion.gentle) {
            open = (open == editor) ? nil : editor
        }
    }

    private func chip(title: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isOn ? Theme.Palette.accent.opacity(0.16) : Theme.Palette.cardSurface)
                )
                .foregroundStyle(isOn ? Theme.Palette.accent : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
