# Velura harness

Velura is a SwiftUI app, so nothing on this machine can *run* it: SwiftUI, CoreLocation,
MapKit, ActivityKit and Combine exist only in Apple SDKs. The harness therefore runs in two
lanes — everything that can be executed locally, and a macOS CI lane that builds and
photographs the real app.

```
tools/check.sh                     # parse · glass audit · portable logic tests
tools/logic-tests/                 # SwiftPM package for the Foundation-only slice
.github/workflows/preview-screenshots.yml   # real simulator build + XCUITest screenshots
```

## Lane 1 — local (Windows, git-bash)

```bash
bash tools/check.sh          # everything below
bash tools/check.sh --fast   # skip the SwiftPM build
```

**1. Syntax.** `swiftc -frontend -parse` on every source file. Parse-only, so Apple-module
imports are never resolved — this catches unbalanced braces, broken string interpolation and
half-finished edits, not API misuse.

**2. Liquid Glass audit.** Runs the Apple-skill audit script over the tree
(`.agents/skills/apple-liquid-glass/scripts/audit_liquid_glass.py`) and reports ad-hoc
container use, nested containers, tint sprawl and inert `interactive()` glass. Findings are
leads, not verdicts — read the surrounding layer before changing anything.

**3. Portable logic tests.** `tools/logic-tests` compiles the slice of the app that has no
Apple-only dependency and runs it with Swift Testing on this machine:

| File | Why it is portable |
|---|---|
| `Velura/DriveModels.swift` | Codable value types, Foundation only |
| `Velura/DriveFileStorage.swift` | `FileManager` + `JSONEncoder` |
| `Velura/DrivingInsightsCalculator.swift` | pure math over drives |
| `Velura/GPXExporter.swift` | string/XML generation |

`tools/logic-tests/prepare.py` copies those files into the package (`Sources/VeluraCore/` is
generated and git-ignored — never edit it). 8 tests, ~0.03 s:

```bash
python tools/logic-tests/prepare.py
swift test --package-path tools/logic-tests
```

`VeluraTests/VeluraTests.swift` (32 tests, device-side) remains the full suite; it needs
XCTest + CoreLocation and runs in the `build-ipa` workflow.

## Lane 2 — macOS CI (the only truth about rendering)

SwiftUI cannot be photographed anywhere else. `Screenshot harness`
(`.github/workflows/preview-screenshots.yml`) boots an iPhone simulator, pre-grants location so
the permission alert never covers the UI, then runs `VeluraUITests/VeluraScreenShots`, which
walks the app and attaches a full-screen capture at every stop:

`01-speed` · `02-drive-mode` · `03-acceleration` · `04-drives` · `05-settings-top` ·
`06-settings-appearance` · `07-settings-bottom` · `08-speed-after-tour` ·
`10-speed-active-drive` · `11-drives-with-record`

```bash
gh workflow run preview-screenshots.yml --ref <branch>
gh run watch
gh run download <run-id> -n velura-screenshots-<run-number> -D screenshots/
```

Triggered automatically on `harness/**` and `glass/**` branch pushes, and on demand.

### Reading the captures honestly

- Simulator glass is close to device glass but **not** identical — parallax, specular
  highlights and backdrop sampling depend on real content and motion. Use captures for
  layout, hierarchy and material correctness; never as proof that a *specific* pixel is right.
- Screenshots of Liquid Glass also change with wallpaper/appearance. Capture in one appearance
  at a time and compare like with like.
- `simctl` overrides the status bar (9:41, full battery) so shots are diffable.

## Reference

- `.agents/skills/liquid-glass/` — material rules, availability, review checklist
- `.agents/skills/liquid-glass-motion/` — morphing, transitions, profiling
- `.agents/skills/apple-liquid-glass/` — audit script + migration notes
