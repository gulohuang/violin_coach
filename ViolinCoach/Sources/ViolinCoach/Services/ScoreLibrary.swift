import Foundation

/// Loads the bundled sample score(s). A real "Creator Studio"-style import
/// flow (pick a .musicxml file from Files/iCloud) is straightforward to add
/// on top of `MusicXMLParser.parse(contentsOf:)` later; out of scope for
/// this first version, which ships with one built-in piece so all three
/// tabs have something to work with immediately.
public enum ScoreLibrary {
    public static func loadBundledSample() -> Result<Score, Error> {
        // Gavotte (P. Martini), 89 bars of single-voice violin. Uncompressed
        // MusicXML extracted from the .mxl the piece shipped as — .mxl is a
        // zip container, and unpacking it at build time keeps the parser free
        // of archive handling.
        guard let url = Bundle.main.url(forResource: "gavotte", withExtension: "musicxml") else {
            return .failure(MusicXMLParseError.noPlayableNotes)
        }
        do {
            return .success(try MusicXMLParser.parse(contentsOf: url))
        } catch {
            return .failure(error)
        }
    }
}
