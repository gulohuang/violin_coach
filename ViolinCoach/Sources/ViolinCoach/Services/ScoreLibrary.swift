import Foundation

/// Loads the bundled sample score(s). A real "Creator Studio"-style import
/// flow (pick a .musicxml file from Files/iCloud) is straightforward to add
/// on top of `MusicXMLParser.parse(contentsOf:)` later; out of scope for
/// this first version, which ships with one built-in piece so all three
/// tabs have something to work with immediately.
public enum ScoreLibrary {
    public static func loadBundledSample() -> Result<Score, Error> {
        guard let url = Bundle.main.url(forResource: "twinkle-twinkle", withExtension: "musicxml") else {
            return .failure(MusicXMLParseError.noPlayableNotes)
        }
        do {
            return .success(try MusicXMLParser.parse(contentsOf: url))
        } catch {
            return .failure(error)
        }
    }
}
