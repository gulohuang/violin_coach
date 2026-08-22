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

What *is* verified: `PitchMath`'s algorithms were modelled and checked
numerically before being written in Swift — the YIN implementation was ported
to Python and run against synthetic violin-range tones (all within 0.014%),
against a weak-fundamental violin timbre to confirm it does *not* drop
octaves, and against noise and silence to confirm rejection. The score
row-packing and tap hit-testing were likewise round-tripped in Python at
several screen widths. `PitchMathTests` and `ScoreRendererSpellingTests`
encode those same cases. So the *math* is trustworthy; the *Swift/Xcode
integration* is not yet.

Note the web prototype under `app/` has **diverged**: it still uses the
original autocorrelation detector (12 passing Vitest tests) and was the
starting point, but the Swift side has since moved to YIN. Treat `app/` as
history, not as the reference implementation.

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
- **YIN, not plain autocorrelation or FFT.** A bowed string's fundamental is
  often weaker than its overtones. That defeats spectral peak-picking, and it
  also makes plain autocorrelation drop octaves, since its peak grows at longer
  lags. YIN's cumulative mean normalization removes that bias, and it returns a
  *clarity* value (1 - aperiodicity) for free — which is what lets the detector
  distinguish "no clear pitch" from "a pitch" instead of only asking whether the
  signal was loud enough.
- **Keep YIN's global-minimum fallback.** When no lag dips below the paper's
  0.15 threshold, standard YIN falls back to the global minimum of the CMNDF.
  Removing that fallback looks like a purity win and is a silent disaster: real
  playing through a real microphone frequently never dips below 0.15, so the
  detector returns nothing at all while the global minimum sits on the correct
  pitch at ~0.85 clarity. Synthetic test tones always dip, so unit tests pass
  and the app is dead. Whether a candidate is good enough is `minimumClarity`'s
  call, not the dip finder's.
- **Sensitivity is a confidence threshold, not a volume gate.**
  `PitchDetector.Sensitivity` maps five levels onto a `minimumClarity` floor
  (0.90 down to 0.30), with a small RMS floor kept only as a cheap early-out on
  silent buffers. Values come from measuring clarity on a violin timbre at
  rising noise: clean ~1.0, badly degraded ~0.34, white noise 0.05–0.07. A loud bow
  scratch passes any loudness test but scores badly on periodicity, which is
  the whole point. Practice defaults to `.highest`: it already knows which
  note it wants, and the ±38 cent window plus three consecutive readings do
  the filtering.
- **Hand-rolled MusicXML parser** (`Foundation.XMLParser`, SAX-style). Keeps
  VexFoundation as the only third-party dependency. MusicXML is just XML;
  staff engraving is the genuinely hard part worth a dependency.
- **One `Stave` per measure, wrapped into rows that scroll vertically.**
  VexFoundation's `System` is for stacking *simultaneous* staves
  (multi-instrument scores), not successive measures of one part, so
  `ScoreRenderer` does its own row packing: it fits as many measures per row
  as `minMeasureWidth` allows, then justifies them to end flush. Every row
  repeats the clef and key signature (only row 0 gets the time signature),
  as printed music does.
- **A stave is 13 line-spacings tall, not 5.** VexFoundation reserves
  `spaceAboveStaffLn` (4) above the top line and `spaceBelowStaffLn` (4)
  below the bottom one, so its full extent from its own y origin is
  `4 + 5 + 4` spacings — see `Stave.getBottomY()`. `ScoreRenderer.staveExtentInSpaces`
  encodes this. Sizing a canvas by the five staff lines alone silently crops
  the clef and every stem, which is exactly the bug it was written to fix.
- **Audio engines never touch the main thread.** `AVAudioSession.setActive`,
  `AVAudioEngine.prepare()`/`.start()`/`.stop()` are synchronous CoreAudio
  calls that block for hundreds of milliseconds. `PitchDetector` and
  `ScoreAudioPlayer` each keep their engine in a `nonisolated`
  `@unchecked Sendable` box touched only on a private serial queue, and flip
  their `@Published` state on the main actor *first* so buttons respond on
  tap rather than after teardown. Pitch analysis gets its own queue on top of
  that, with drop-if-busy backpressure — never queue audio work you can drop.
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
│   │   └── Resources/gavotte.musicxml
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
xcrun simctl launch booted com.gulohuang.violincoach
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

### Code signing

The bundle ID (`PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`) is globally
unique across every Apple developer account, so it must be namespaced to a
domain/account you control. Simulator builds need no signing at all — if
Xcode is trying to register the identifier with your team, you have a
physical device selected, or a team set on a target that doesn't need one.

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
- **Accidentals follow the written spelling and the key signature.**
  `ScoreNote` keeps `step`/`alter` from the MusicXML alongside `midi`, because
  MIDI alone cannot tell B♭ from A♯. An accidental prints only where the note
  departs from the key signature — deriving it from `alter` alone put a sharp
  on all 40 F naturals in the Gavotte, which is in G major.
- **No auto-scroll to cursor** — the score scrolls by hand.
- **One bundled score** — Gavotte (P. Martini), 89 bars of single-voice
  violin, extracted from its `.mxl` (a zip container) at authoring time. The
  parser reads plain MusicXML only; `.mxl` support would mean adding archive
  handling. A file-import flow on top of `MusicXMLParser.parse(contentsOf:)`
  is the natural next step.
- **Never set a fill or stroke style before `factory.draw()`.** The render
  context is stateful, so a style set while laying out staves is still current
  when VexFoundation engraves the notation and will tint the noteheads with
  it. A section highlight drawn that way made every note translucent blue.
  Draw overlays *after* `factory.draw()`, wrapped in `save()`/`restore()`.
- **Notation rendered**: beams, slurs, staccato/staccatissimo/accent/tenuto/
  marcato/fermata, up- and down-bow, left-hand fingerings, and dynamics.
  **Still dropped**: hairpins (`<wedge>`), text directions (`<words>`),
  breath marks, and non-primary beam levels. Notation lives on `ScoreNote`
  but never feeds practice or playback — those read only `midi` and
  `beatsInQuarters`, so engraving can change without touching either.
- **Synthesized tone, not sampled violin** — a harmonic stack with an
  envelope, chosen to keep the app dependency-free and small.

## Conventions

- Comments explain *why*, not *what*. Existing comments document the reasoning
  behind non-obvious choices (why autocorrelation, why per-measure staves,
  why the tolerance values are what they are) — match that.
- Practice-mode tolerances (`PracticeViewModel`): ±38 cents, and the note must
  be *sustained* for `0.6 ×` its written duration, clamped to 0.18–1.2s. Pitch
  alone let you skate through a slow passage at any speed; the clamp keeps
  sixteenths responsive and stops a whole note becoming a stamina test.
  Change these only with a reason.
- **The hold clock runs on a timer, not on pitch readings.** `PitchDetector`
  suppresses readings identical to the last one, so a perfectly steady note
  stops publishing — checking the hold only when a reading arrives would mean
  it never completes. `PracticeViewModel` ticks at 20Hz while active, which
  also keeps the hold progress bar smooth between readings.
- New Service code: keep pure logic separable from AVFoundation so it stays
  testable without hardware.
