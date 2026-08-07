# ViolinCoach

A lightweight iOS violin practice app: chromatic tuner, score playback with a
following cursor, and note-by-note practice with real-time pitch feedback.

## ⚠️ Verification status — read this first

**The native iOS app in `ViolinCoach/` has never been compiled, run, or
tested.** It was authored in a Linux container with no macOS, no Xcode, no
Swift toolchain, and no simulator. Every API call in it was written against
VexFoundation's actual source (cloned and read at commit `252b9a7`) and its
DocC guides rather than from memory — but reading source is not the same as
compiling against it. Assume the first `xcodebuild` will surface errors and
budget time for a fix-up pass.

What *is* verified: the algorithms were first built and tested in the web
prototype under `app/` (12 passing Vitest tests for pitch detection against
synthetic violin-range sine waves). `PitchMath.swift` is a line-by-line port
of that validated TypeScript, and `PitchMathTests.swift` ports the same test
cases. So the *math* is trustworthy; the *Swift/Xcode integration* is not yet.

First job on a Mac:

```bash
brew install xcodegen        # one-time
cd ViolinCoach && xcodegen generate
xcodebuild -scheme ViolinCoach -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild test -scheme ViolinCoach -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Architecture

**SwiftUI + MVVM.** No UIKit except where SwiftUI needs it (none currently).
Deployment target **iOS 16.0**, Swift 6.

Layering, strictly one-directional (`Views → ViewModels → Services → Models`):

- **Models** (`Sources/ViolinCoach/Models/`) — plain `Sendable` value types.
  `Score`, `ScoreNote`, `ScoreMeasure`. No framework imports beyond Foundation.
- **Services** (`Sources/ViolinCoach/Services/`) — the engine room. Audio I/O,
  DSP, parsing. Each is independently testable; the pure-math parts are
  deliberately split out from the AVFoundation parts so tests don't need
  audio hardware.
- **Notation** (`Sources/ViolinCoach/Notation/`) — `ScoreRenderer`, the bridge
  from our `Score` model to VexFoundation's engraving API.
- **ViewModels** (`Sources/ViolinCoach/ViewModels/`) — `@MainActor
  ObservableObject`s holding per-tab state. Views read published properties;
  no view touches a Service directly except through its ViewModel.
- **Views** (`Sources/ViolinCoach/Views/`) — SwiftUI, as dumb as practical.

### The three tabs

| Tab | View | ViewModel | Engine |
|---|---|---|---|
| Tuner | `TunerView` | `TunerViewModel` | `PitchDetector` → `PitchMath` |
| Score Player | `ScorePlayerView` | `ScorePlayerViewModel` | `ScoreAudioPlayer` → `ToneSynthesizer` |
| Practice | `PracticeView` | `PracticeViewModel` | `PitchDetector` + `ScoreRenderer` |

### The one invariant worth knowing

`Score.playableNotes` (non-rest notes, in order) defines a single index space
shared by **everything** that tracks position: `ScoreAudioPlayer.currentIndex`,
`PracticeViewModel.currentIndex`, and `RenderedNotePosition.playableIndex`.
That's what keeps "what's sounding," "what note we're waiting for," and
"where the cursor is drawn" from ever drifting apart. If you add a feature
that tracks position, index into `playableNotes` — don't invent a parallel
numbering.

### Key design decisions

- **Pure math split from audio I/O.** `PitchMath` (autocorrelation, cents,
  MIDI conversion) has zero AVFoundation dependency, so it's unit-testable
  without a mic. `PitchDetector` is the thin AVAudioEngine tap on top.
  Same split for `ToneSynthesizer` (buffer rendering) vs `ScoreAudioPlayer`.
- **Autocorrelation, not FFT.** A bowed string's fundamental is often weaker
  than its overtones, which defeats naive spectral peak-picking.
- **Hand-rolled MusicXML parser** (`Foundation.XMLParser`, SAX-style). Keeps
  VexFoundation as the only third-party dependency. MusicXML is just XML;
  staff engraving is the genuinely hard part worth a dependency.
- **One `Stave` per measure, laid out left-to-right in a horizontal
  ScrollView.** VexFoundation's `System` is for stacking *simultaneous*
  staves (multi-instrument scores), not successive measures of one part.
  A single scrolling line avoids implementing line-breaking, and suits
  follow-along practice.
- **XcodeGen `project.yml` instead of a checked-in `.xcodeproj`.** A pbxproj
  is a large generated format meant for Xcode's GUI to edit — hand-editing or
  agent-editing it invites corruption. YAML is diffable and regenerates
  deterministically.

## Dependencies (SPM)

- **[VexFoundation](https://github.com/migueldeicaza/VexFoundation)** — Swift
  port of VexFlow; music engraving (`Factory`, `Stave`, `StaveNote`, `Voice`,
  `Formatter`, `VexCanvas`). Pinned to revision `252b9a7a9cc6583dbff50f984bf33e8448bce72f`
  — no tagged release existed at time of writing. Re-pin to a version once one ships.

Everything else is Apple-platform: SwiftUI, AVFoundation, Combine, Foundation.

## Folder structure

```
violin_coach/
├── CLAUDE.md                    # this file
├── .mcp.json                    # ios-simulator MCP server
├── .claude/settings.json        # swift/git/xcodebuild permissions
├── ViolinCoach/                 # the iOS app (UNVERIFIED — see above)
│   ├── project.yml              # XcodeGen spec → generates ViolinCoach.xcodeproj
│   ├── Sources/ViolinCoach/
│   │   ├── ViolinCoachApp.swift # @main
│   │   ├── Models/Score.swift
│   │   ├── Services/            # MusicXMLParser, PitchMath, PitchDetector,
│   │   │                        # ToneSynthesizer, ScoreAudioPlayer, ScoreLibrary
│   │   ├── Notation/ScoreRenderer.swift
│   │   ├── ViewModels/          # Tuner, ScorePlayer, Practice
│   │   ├── Views/               # ContentView (TabView) + 3 tabs + ScoreCanvasView
│   │   └── Resources/twinkle-twinkle.musicxml
│   └── Tests/ViolinCoachTests/  # XCTest — NEVER RUN, see above
└── app/                         # web prototype (VERIFIED: builds, 12 tests pass)
    └── src/lib/                 # pitchDetection.ts + .test.ts — the reference
                                 # implementation the Swift port derives from
```

## Build / test / run loop

There is no Xcode GUI access; drive everything from the CLI.

```bash
# Regenerate the project after ANY change to project.yml, or after adding/
# removing/renaming source files (XcodeGen globs the Sources dir).
cd ViolinCoach && xcodegen generate

# Build
xcodebuild -scheme ViolinCoach -destination 'platform=iOS Simulator,name=iPhone 16' build

# Test (XCTest; Swift Testing also works with this invocation)
xcodebuild test -scheme ViolinCoach -destination 'platform=iOS Simulator,name=iPhone 16'

# Quieter output if xcbeautify is installed
xcodebuild ... | xcbeautify
```

Simulator control via `xcrun simctl`:

```bash
xcrun simctl list devices available
xcrun simctl boot "iPhone 16"
xcrun simctl install booted /path/to/ViolinCoach.app
xcrun simctl launch booted com.violincoach.app
xcrun simctl io booted screenshot /tmp/shot.png
```

The **ios-simulator MCP server** (configured in `.mcp.json`) is the better
path for anything interactive — booting, tapping, swiping, screenshots —
because it returns results into the conversation instead of requiring
screenshot round-trips. Install with:

```bash
claude mcp add ios-simulator -- npx -y ios-simulator-mcp
```

XcodeBuildMCP is a reasonable alternative/complement for higher-level
build-run-test orchestration. Xcode 26.3+ also ships a native Xcode MCP.

### Microphone testing caveat

The simulator forwards the **Mac's** microphone. Tuner and Practice tabs need
a real pitch source: play a tuner app through speakers, or test on a device.
Simulator audio input is often silent by default — check
*Simulator → Settings → Microphone* before concluding the detector is broken.

## Known limitations (deliberate, documented)

- Only the **first `<part>`** of a MusicXML file is read (solo line).
- **Chords collapse to their first note** — this app is monophonic by design.
- **Ties are not merged**: a note tied across a barline becomes two attacks.
  Correct visually, slightly wrong for practice timing on tied pieces.
- **Grace notes are skipped** (no `<duration>` element).
- **Accidentals always spell as sharps** (F♯, never G♭). Correct key-aware
  enharmonic spelling is a real feature, not yet built.
- **No auto-scroll to cursor** — the score scrolls by hand.
- **One bundled score.** A file-import flow on top of
  `MusicXMLParser.parse(contentsOf:)` is the natural next step.
- **Synthesized tone, not sampled violin** — a harmonic stack with an
  envelope, chosen to keep the app dependency-free and small.

## Conventions

- Comments explain *why*, not *what*. Existing comments document the reasoning
  behind non-obvious choices (why autocorrelation, why per-measure staves,
  why the tolerance values are what they are) — match that.
- Practice-mode tolerances (`PracticeViewModel`): ±38 cents, 3 consecutive
  in-tune readings before advancing. Loose enough for bow/vibrato wobble,
  tight enough to mean something, fast enough to feel responsive. Change
  these only with a reason.
- New Service code: keep pure logic separable from AVFoundation so it stays
  testable without hardware.
