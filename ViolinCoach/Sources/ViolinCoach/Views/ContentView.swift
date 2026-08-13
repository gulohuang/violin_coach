import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TunerView()
                .tabItem { Label("Tuner", systemImage: "tuningfork") }

            ScorePlayerView()
                .tabItem { Label("Score Player", systemImage: "play.circle") }

            PracticeView()
                .tabItem { Label("Practice", systemImage: "waveform.path.ecg") }
        }
        // Propagates the brand accent to every control in the app. Done here
        // rather than via an asset catalog's AccentColor so the palette stays
        // in one reviewable Swift file.
        .tint(Theme.Palette.accent)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
