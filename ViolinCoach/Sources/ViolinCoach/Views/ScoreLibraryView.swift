import SwiftUI
import UniformTypeIdentifiers

/// The folder both score tabs open on: every saved score, listed for
/// selection. Picking one pushes the tab's own screen; the navigation bar's
/// back button returns here.
///
/// This is a plain `List` of `NavigationLink(value:)` rows rather than a
/// custom grid. A list of pieces is exactly what a `List` is for, and using
/// the system one means swipe-to-delete, the pushed back button, and Dynamic
/// Type all come for free and behave the way they do everywhere else on the
/// device.
struct ScoreLibraryView: View {
    @ObservedObject var library: ScoreLibraryViewModel
    /// One line under the title saying what selecting a score will do, since
    /// the same folder fronts two very different screens.
    let prompt: String

    @State private var isImporting = false

    /// `.musicxml` has no registered system type, so it's resolved by
    /// extension and `.xml` is allowed alongside it — plenty of publishers
    /// hand out MusicXML with a plain `.xml` name.
    private var allowedTypes: [UTType] {
        var types: [UTType] = [.xml]
        if let musicXML = UTType(filenameExtension: "musicxml") {
            types.insert(musicXML, at: 0)
        }
        return types
    }

    var body: some View {
        List {
            Section {
                ForEach(library.entries) { entry in
                    NavigationLink(value: entry) {
                        row(for: entry)
                    }
                }
                // Wrapped rather than passed as `perform: library.delete`:
                // the method is main-actor isolated and `onDelete`'s parameter
                // type isn't, so the closure is what keeps the hop explicit.
                .onDelete { offsets in library.delete(at: offsets) }
            } header: {
                Text(prompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            } footer: {
                if library.entries.isEmpty && !library.isLoading {
                    Text("No scores yet. Add an uncompressed MusicXML file (.musicxml or .xml).")
                        .font(.footnote)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isImporting = true
                } label: {
                    Label("Add Score", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { library.importScore(from: url) }
            case .failure(let error):
                library.importError = error.localizedDescription
            }
        }
        // `isPresented` bound to a computed non-nil check, because the message
        // itself is the state — there's no separate "an error happened" flag
        // to drift out of sync with it.
        .alert(
            "Couldn't add that score",
            isPresented: Binding(
                get: { library.importError != nil },
                set: { if !$0 { library.importError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { library.importError = nil }
        } message: {
            Text(library.importError ?? "")
        }
        // `refreshable`'s action is a detached async closure, so reaching the
        // main-actor view model from it has to be awaited.
        .refreshable { await MainActor.run { library.refresh() } }
    }

    private func row(for entry: ScoreEntry) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(entry.origin == .bundled ? "Included" : "Added by you")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ScoreLibraryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ScoreLibraryView(library: ScoreLibraryViewModel(), prompt: "Choose a score to play")
                .navigationTitle("Scores")
        }
    }
}
