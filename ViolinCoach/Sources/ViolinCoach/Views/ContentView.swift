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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
