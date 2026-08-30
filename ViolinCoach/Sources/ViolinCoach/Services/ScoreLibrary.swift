import Foundation

/// One score the app can open: a bundled piece, or one the player imported.
public struct ScoreEntry: Identifiable, Hashable, Sendable {
    public enum Origin: Sendable, Hashable {
        /// Ships with the app; always present, can't be deleted.
        case bundled
        /// Copied into the app's Documents folder by the player.
        case imported
    }

    public let url: URL
    public let title: String
    public let origin: Origin

    /// The file path, so a list selection survives the library being rescanned.
    public var id: String { url.path }

    public init(url: URL, title: String, origin: Origin) {
        self.url = url
        self.title = title
        self.origin = origin
    }
}

public enum ScoreLibraryError: LocalizedError {
    case unreadableFile

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "That file couldn't be read. Scores must be uncompressed MusicXML (.musicxml or .xml) — .mxl files are zip archives and aren't supported yet."
        }
    }
}

/// The folder of saved scores behind the Score Player and Practice tabs.
///
/// Two places are scanned and merged: the app bundle, which always has at
/// least the built-in piece so a fresh install has something to play, and
/// `Documents/Scores`, where imports land. Imports go to Documents rather than
/// Caches deliberately — these are the player's own files and shouldn't be
/// evicted under storage pressure.
public enum ScoreLibrary {

    /// Uncompressed MusicXML only. `.mxl` is a zip container, and unpacking one
    /// would mean adding archive handling to an app whose parser is otherwise
    /// pure `XMLParser`.
    public static let supportedExtensions = ["musicxml", "xml"]

    public static var importedScoresDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Scores", isDirectory: true)
    }

    /// Every score available to open, bundled first, then imports A–Z.
    ///
    /// Titles come from `MusicXMLParser.parseTitle`, which reads only the file
    /// header. A file whose header has no title falls back to its filename
    /// rather than being hidden — a score you can see and open beats a
    /// perfectly-labelled list that silently drops files.
    public static func entries() -> [ScoreEntry] {
        var entries = bundledEntries()
        entries.append(contentsOf: importedEntries())
        return entries
    }

    static func bundledEntries() -> [ScoreEntry] {
        supportedExtensions
            .flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
            .map { entry(for: $0, origin: .bundled) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func importedEntries() -> [ScoreEntry] {
        let directory = importedScoresDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { entry(for: $0, origin: .imported) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func entry(for url: URL, origin: ScoreEntry.Origin) -> ScoreEntry {
        let title = MusicXMLParser.parseTitle(contentsOf: url)
            ?? url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ").capitalized
        return ScoreEntry(url: url, title: title, origin: origin)
    }

    public static func load(_ entry: ScoreEntry) -> Result<Score, Error> {
        do {
            return .success(try MusicXMLParser.parse(contentsOf: entry.url))
        } catch {
            return .failure(error)
        }
    }

    /// Copies a picked file into the library.
    ///
    /// The file is parsed *before* it's saved, so a file that can't be read
    /// fails here — at the moment the player chose it, with the picker still
    /// fresh in mind — rather than becoming a row that errors every time it's
    /// tapped.
    @discardableResult
    public static func importScore(from source: URL) throws -> ScoreEntry {
        // Files handed over by the document picker live outside the sandbox and
        // need this to be readable at all. Some sources (already-local files)
        // return false, which is not an error — hence no `guard`.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: source) else {
            throw ScoreLibraryError.unreadableFile
        }
        // Throws for malformed XML or a file with no playable notes.
        _ = try MusicXMLParser.parse(data: data)

        let directory = importedScoresDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = uniqueDestination(for: source.lastPathComponent, in: directory)
        try data.write(to: destination, options: .atomic)
        return entry(for: destination, origin: .imported)
    }

    /// Keeps a second "gavotte.musicxml" from overwriting the first.
    private static func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let base = (filename as NSString).deletingPathExtension
        var ext = (filename as NSString).pathExtension.lowercased()
        if !supportedExtensions.contains(ext) { ext = "musicxml" }

        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }

    /// Removes an imported score. Bundled scores are part of the app and are
    /// silently left alone rather than throwing — the UI doesn't offer to
    /// delete them in the first place.
    public static func delete(_ entry: ScoreEntry) throws {
        guard entry.origin == .imported else { return }
        try FileManager.default.removeItem(at: entry.url)
    }
}
