import Foundation

/// Backs the folder screen the Score Player and Practice tabs open on.
///
/// Each tab owns its own instance rather than sharing one: they're separate
/// navigation stacks, and one tab rescanning after an import shouldn't yank
/// the other tab's list out from under it mid-scroll. Rescanning is cheap —
/// a directory listing plus a header-only parse per file.
@MainActor
public final class ScoreLibraryViewModel: ObservableObject {
    @Published public private(set) var entries: [ScoreEntry] = []
    /// Surfaced to the view as an alert; cleared when dismissed.
    @Published public var importError: String?
    @Published public private(set) var isLoading = false

    public init() {
        refresh()
    }

    public func refresh() {
        isLoading = true
        // Scanning touches the filesystem and parses each file's header, so it
        // stays off the main actor — with a dozen scores that's imperceptible,
        // but the folder screen shouldn't be the thing that hitches on a
        // player who has collected a hundred.
        Task.detached(priority: .userInitiated) {
            let found = ScoreLibrary.entries()
            await MainActor.run {
                self.entries = found
                self.isLoading = false
            }
        }
    }

    public func importScore(from url: URL) {
        do {
            try ScoreLibrary.importScore(from: url)
            refresh()
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Deletes by offsets, which is the shape `onDelete` hands over. Bundled
    /// scores are skipped rather than erroring — the swipe isn't offered on
    /// them, so reaching here with one means something else went wrong and
    /// removing a file from the app bundle is not the recovery.
    public func delete(at offsets: IndexSet) {
        for index in offsets where entries.indices.contains(index) {
            let entry = entries[index]
            guard entry.origin == .imported else { continue }
            do {
                try ScoreLibrary.delete(entry)
            } catch {
                importError = error.localizedDescription
            }
        }
        refresh()
    }
}
